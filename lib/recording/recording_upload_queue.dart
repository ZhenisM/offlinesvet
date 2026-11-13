import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:offlinesvet/recording/recording_api.dart';
import 'package:offlinesvet/recording/recording_config.dart';

/// Задача очереди: кусок записи или событие сессии.
class RecordingJob {
  final String id; // для куска — "<session>:<seq>", для события — event_id
  final String kind; // chunk | event
  final String sessionId;
  final String token; // токен менеджера на момент записи (планшет общий)
  final DateTime at; // начало куска / время события
  // chunk
  final int? seq;
  final int? durationMs;
  final String? filePath;
  final String? fragmentId; // уникальный ID куска (UUID)
  final String? cartId; // корзина, к которой относится кусок
  final String? stage; // этап консультации на момент окончания куска
  // event
  final String? type;
  final Map<String, dynamic>? data;

  int attempts;
  bool failed;
  String? lastError;

  RecordingJob({
    required this.id,
    required this.kind,
    required this.sessionId,
    required this.token,
    required this.at,
    this.seq,
    this.durationMs,
    this.filePath,
    this.fragmentId,
    this.cartId,
    this.stage,
    this.type,
    this.data,
    this.attempts = 0,
    this.failed = false,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'sessionId': sessionId,
        'token': token,
        'at': at.toIso8601String(),
        'seq': seq,
        'durationMs': durationMs,
        'filePath': filePath,
        'fragmentId': fragmentId,
        'cartId': cartId,
        'stage': stage,
        'type': type,
        'data': data,
        'attempts': attempts,
        'failed': failed,
        'lastError': lastError,
      };

  factory RecordingJob.fromJson(Map<String, dynamic> j) => RecordingJob(
        id: j['id'] as String,
        kind: j['kind'] as String,
        sessionId: j['sessionId'] as String,
        token: j['token'] as String? ?? '',
        at: DateTime.parse(j['at'] as String),
        seq: j['seq'] as int?,
        durationMs: j['durationMs'] as int?,
        filePath: j['filePath'] as String?,
        fragmentId: j['fragmentId'] as String?,
        cartId: j['cartId'] as String?,
        stage: j['stage'] as String?,
        type: j['type'] as String?,
        data: (j['data'] as Map?)?.cast<String, dynamic>(),
        attempts: j['attempts'] as int? ?? 0,
        failed: j['failed'] as bool? ?? false,
        lastError: j['lastError'] as String?,
      );
}

/// Очередь отправки кусков и событий — строго по порядку, на диске,
/// переживает плохую сеть и перезапуск приложения. Куски пишутся в
/// `<support>/recording/chunks/`, файл удаляется после приёма сервером.
class RecordingUploadQueue {
  RecordingUploadQueue._();
  static final RecordingUploadQueue instance = RecordingUploadQueue._();

  static const _baseRetry = Duration(seconds: 5);
  static const _maxRetry = Duration(minutes: 5);
  static const _keepFailed = Duration(days: 7);

  final _api = RecordingApi();
  final List<RecordingJob> _queue = [];
  bool _restored = false;
  bool _processing = false;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;
  Future<void> _saveChain = Future.value();

  /// Сколько задач ждут отправки — для индикации на кнопке записи.
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  Directory? _dir;

  Future<Directory> _baseDir() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await getApplicationSupportDirectory()).path}/recording');
    await Directory('${d.path}/chunks').create(recursive: true);
    return _dir = d;
  }

  Future<String> chunkPath(String sessionId, int seq) async =>
      '${(await _baseDir()).path}/chunks/${sessionId}_${seq.toString().padLeft(6, '0')}.wav';

  Future<File> _queueFile() async => File('${(await _baseDir()).path}/queue.json');

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final f = await _queueFile();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List<dynamic>;
        final restored = list.map((e) => RecordingJob.fromJson((e as Map).cast<String, dynamic>())).toList();
        // Добавляем ПЕРЕД тем, что успело встать в очередь за время чтения.
        _queue.insertAll(0, restored);
      }
      // Застрявшие отклонённые задачи старше недели — убираем вместе с файлами.
      final cutoff = DateTime.now().subtract(_keepFailed);
      final stale = _queue.where((j) => j.failed && j.at.isBefore(cutoff)).toList();
      for (final j in stale) {
        _queue.remove(j);
        if (j.filePath != null) {
          try { await File(j.filePath!).delete(); } catch (_) {}
        }
      }
      await _persist();
    } catch (e) {
      debugPrint('RecordingUploadQueue.restore: не удалось прочитать очередь ($e)');
    }
    unawaited(_processNext());
  }

  void _updateCount() => pendingCount.value = _queue.where((j) => !j.failed).length;

  /// Запись на диск последовательно (tmp + rename), чтобы файл очереди
  /// не побился, если приложение закроют посреди записи.
  Future<void> _persist() {
    _updateCount();
    final snapshot = jsonEncode(_queue.map((j) => j.toJson()).toList());
    _saveChain = _saveChain.then((_) async {
      try {
        final f = await _queueFile();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(snapshot, flush: true);
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('RecordingUploadQueue: не удалось сохранить очередь ($e)');
      }
    });
    return _saveChain;
  }

  Future<void> add(RecordingJob job) async {
    if (_queue.any((j) => j.id == job.id)) return;
    _queue.add(job);
    await _persist();
    unawaited(_processNext());
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    // 5 с, 10, 20, 40 … максимум 5 минут.
    final factor = 1 << (_consecutiveFailures.clamp(1, 7) - 1);
    final delay = _baseRetry * factor;
    _retryTimer = Timer(delay > _maxRetry ? _maxRetry : delay, _processNext);
  }

  /// Принудительно попробовать сейчас (например, появилась сеть).
  void kick() {
    _consecutiveFailures = 0;
    unawaited(_processNext());
  }

  Future<void> _processNext() async {
    if (_processing) return;
    final idx = _queue.indexWhere((j) => !j.failed);
    if (idx < 0) return;

    _processing = true;
    _retryTimer?.cancel();
    final job = _queue[idx];
    var again = false;

    try {
      job.attempts++;
      if (job.kind == 'chunk') {
        final path = job.filePath;
        if (path == null || !await File(path).exists()) {
          throw RecordingApiException('Файл куска пропал с устройства', permanent: true);
        }
        await _api.sendChunk(
          token: job.token,
          sessionId: job.sessionId,
          seq: job.seq ?? 0,
          startedAt: job.at,
          durationMs: job.durationMs ?? 0,
          filePath: path,
          fragmentId: job.fragmentId ?? job.id,
          cartId: job.cartId,
          stage: job.stage,
        );
        try { await File(path).delete(); } catch (_) {}
      } else {
        final res = await _api.sendEvent(
          token: job.token,
          sessionId: job.sessionId,
          eventId: job.id,
          type: job.type ?? '',
          at: job.at,
          data: job.data ?? const {},
        );
        final cs = res['chunk_seconds'];
        if (job.type == 'session_started' && cs is int) {
          await RecordingConfig.saveServerChunkSeconds(cs);
        }
      }
      _queue.remove(job);
      _consecutiveFailures = 0;
      await _persist();
      again = true;
    } on RecordingApiException catch (e) {
      job.lastError = e.toString();
      if (e.permanent) {
        // Не блокируем очередь: помечаем и идём дальше. Файл куска
        // остаётся на устройстве до очистки через неделю.
        debugPrint('Recording: ${job.kind} ${job.id} отклонён ($e)');
        job.failed = true;
        await _persist();
        again = true;
      } else {
        debugPrint('Recording: ${job.kind} ${job.id} не ушёл, повторю ($e)');
        _consecutiveFailures++;
        await _persist();
        _scheduleRetry();
      }
    } catch (e) {
      job.lastError = e.toString();
      debugPrint('Recording: ${job.kind} ${job.id} ошибка, повторю ($e)');
      _consecutiveFailures++;
      await _persist();
      _scheduleRetry();
    } finally {
      _processing = false;
      if (again) unawaited(_processNext());
    }
  }
}
