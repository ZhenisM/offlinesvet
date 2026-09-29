import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/foursell/foursell_api.dart';
import 'package:offlinesvet/foursell/foursell_config.dart';

/// Одна коммуникация (разговор под анкету) к отправке в 4sell.
///
/// communicationId — НАШ ID, сгенерированный в момент открытия анкеты.
/// Он же order_id в 4sell и он же ORIGIN_ID у лида в Bitrix — так запись
/// в 4sell и лид связываются без участия 4sell.
class FourSellJob {
  final String communicationId;
  final String eventId;
  final String filePath; // копия в папке приложения, не temp
  final DateTime startedAt;
  final DateTime endedAt;
  final String? employeeId;
  final String? employeeName;
  final String? leadId; // для логов; у некачественного лида может быть null
  final FourSellFormKind formKind;
  bool orderCreated;
  bool failed;
  String? lastError;
  int attempts;

  FourSellJob({
    required this.communicationId,
    required this.eventId,
    required this.filePath,
    required this.startedAt,
    required this.endedAt,
    this.employeeId,
    this.employeeName,
    this.leadId,
    this.formKind = FourSellFormKind.lead,
    this.orderCreated = false,
    this.failed = false,
    this.lastError,
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'communicationId': communicationId,
        'eventId': eventId,
        'filePath': filePath,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'employeeId': employeeId,
        'employeeName': employeeName,
        'leadId': leadId,
        'formKind': formKind.name,
        'orderCreated': orderCreated,
        'failed': failed,
        'lastError': lastError,
        'attempts': attempts,
      };

  factory FourSellJob.fromJson(Map<String, dynamic> j) => FourSellJob(
        communicationId: j['communicationId'] as String,
        eventId: j['eventId'] as String,
        filePath: j['filePath'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: DateTime.parse(j['endedAt'] as String),
        employeeId: j['employeeId'] as String?,
        employeeName: j['employeeName'] as String?,
        leadId: j['leadId'] as String?,
        formKind: FourSellFormKind.values.firstWhere(
            (k) => k.name == j['formKind'], orElse: () => FourSellFormKind.lead),
        orderCreated: j['orderCreated'] as bool? ?? false,
        failed: j['failed'] as bool? ?? false,
        lastError: j['lastError'] as String?,
        attempts: j['attempts'] as int? ?? 0,
      );
}

/// Фоновая очередь отправки записей в 4sell. Устроена как BadLeadQueue:
/// задача мгновенно ложится на диск, отправка идёт отдельно и
/// переживает плохую сеть и перезапуск приложения.
///
/// На каждую задачу — один POST /order-events (created + audio_file),
/// затем удаление локальной копии файла.
class FourSellUploadQueue {
  FourSellUploadQueue._();
  static final FourSellUploadQueue instance = FourSellUploadQueue._();

  static const _storageKey = 'foursell_pending_jobs';
  static const _baseRetry = Duration(seconds: 30);
  static const _maxRetry = Duration(minutes: 10);

  final _api = FourSellApi();
  final List<FourSellJob> _queue = [];
  bool _processing = false;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;

  /// Сколько записей ждут отправки (без "failed").
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  Future<void> restore() async {
    if (!FourSellConfig.isEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _queue.addAll(list.map((e) => FourSellJob.fromJson(e as Map<String, dynamic>)));
      _updateCount();
      unawaited(_processNext());
    } catch (e) {
      debugPrint('FourSellUploadQueue.restore: не удалось прочитать очередь ($e)');
    }
  }

  void _updateCount() => pendingCount.value = _queue.where((j) => !j.failed).length;

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_queue.map((j) => j.toJson()).toList()));
    _updateCount();
  }

  /// Копирует файл записи в собственную папку (temp может почистить ОС,
  /// а Bitrix-отправка удаляет исходник после успеха) и ставит задачу.
  /// Работает только с диском — вызывать можно прямо с экрана.
  Future<void> enqueue({
    required String communicationId,
    required String recordingPath,
    required DateTime startedAt,
    required DateTime endedAt,
    String? employeeId,
    String? employeeName,
    String? leadId,
    FourSellFormKind formKind = FourSellFormKind.lead,
  }) async {
    if (!FourSellConfig.isEnabled) return;
    final src = File(recordingPath);
    if (!await src.exists()) return;
    if (_queue.any((j) => j.communicationId == communicationId)) return;

    final dir = Directory('${(await getApplicationSupportDirectory()).path}/foursell');
    await dir.create(recursive: true);
    final ext = recordingPath.split('.').last;
    final copy = await src.copy('${dir.path}/$communicationId.$ext');

    _queue.add(FourSellJob(
      communicationId: communicationId,
      eventId: newUuidV4(),
      filePath: copy.path,
      startedAt: startedAt,
      endedAt: endedAt,
      employeeId: employeeId,
      employeeName: employeeName,
      leadId: leadId,
      formKind: formKind,
    ));
    await _persist();
    unawaited(_processNext());
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    // 30с, 60с, 120с ... максимум 10 минут.
    final factor = 1 << (_consecutiveFailures.clamp(1, 5) - 1);
    final delay = _baseRetry * factor;
    _retryTimer = Timer(delay > _maxRetry ? _maxRetry : delay, _processNext);
  }

  Future<void> _processNext() async {
    if (_processing) return;
    final idx = _queue.indexWhere((j) => !j.failed);
    if (idx < 0) return;

    _processing = true;
    _retryTimer?.cancel();
    final job = _queue[idx];
    bool again = false;

    try {
      job.attempts++;
      // Одним запросом: событие created + audio_file (README 2.1).
      await _api.sendCreatedWithAudio(
        orderId: job.communicationId,
        eventId: job.eventId,
        startedAt: job.startedAt,
        endedAt: job.endedAt,
        // employee.employee_id обязателен в схеме DEFAULT.
        employeeId: job.employeeId ?? job.employeeName ?? 'unknown',
        employeeName: job.employeeName,
        formKind: job.formKind,
        audioPath: job.filePath,
      );
      job.orderCreated = true;

      debugPrint('FourSell: запись ${job.communicationId} (лид ${job.leadId ?? "—"}) принята');
      _queue.remove(job);
      _consecutiveFailures = 0;
      await _persist();
      try { await File(job.filePath).delete(); } catch (_) {}
      again = true;
    } on FourSellPermanentException catch (e) {
      // Не повторяем: файл остаётся на устройстве, задача помечена —
      // после правки схемы/ключа её можно перезапустить retryFailed().
      debugPrint('FourSell: задача ${job.communicationId} отклонена ($e)');
      job.failed = true;
      job.lastError = e.toString();
      await _persist();
      again = true;
    } catch (e) {
      debugPrint('FourSell: ${job.communicationId} не отправилась, повторю позже ($e)');
      job.lastError = e.toString();
      _consecutiveFailures++;
      await _persist();
      _scheduleRetry();
    } finally {
      _processing = false;
      if (again) unawaited(_processNext());
    }
  }

  /// Перезапустить отклонённые задачи (например, после исправления
  /// формата запроса новой сборкой).
  Future<void> retryFailed() async {
    for (final j in _queue) {
      j.failed = false;
    }
    await _persist();
    unawaited(_processNext());
  }
}

/// UUID v4 без лишней зависимости.
String newUuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
