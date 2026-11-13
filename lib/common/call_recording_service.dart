import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/customer/models/customer_model.dart';
import 'package:offlinesvet/foursell/foursell_upload_queue.dart' show newUuidV4;
import 'package:offlinesvet/recording/recording_config.dart';
import 'package:offlinesvet/recording/recording_upload_queue.dart';

/// Одна непрерывная запись разговора менеджера с покупателем.
///
/// - Старт: кнопка «Записать разговор» на главном экране, открытие анкеты
///   лида / некачественного лида или микрофон в нижнем меню.
/// - Звук идёт потоком PCM, каждые N секунд (10 по умолчанию) готовый
///   кусок сохраняется в WAV и встаёт в очередь отправки — без пауз между
///   кусками, т.к. микрофон не перезапускается.
/// - Создание лида, выбор клиента, корзина, заказ, сделка — НЕ
///   останавливают запись, а уходят событиями в ту же сессию
///   (session_id) — так приёмник знает, к чему относится разговор.
/// - Остановка: заказ оформлен, кнопка в нижнем меню, 30 минут без
///   касаний экрана, отправка некачественного лида или закрытие анкеты,
///   которая сама запустила запись, без отправки.
///
/// session_id генерируется здесь же и записывается в ORIGIN_ID лида
/// (ORIGINATOR_ID = '4sell'), как и раньше.
class CallRecordingService {
  CallRecordingService._() {
    // Любое касание в любом месте приложения — признак активности.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
    _inactivityChecker = Timer.periodic(const Duration(seconds: 30), (_) => _checkInactivity());
  }

  static final CallRecordingService instance = CallRecordingService._();

  static const _activeKey = 'rec_active_session';

  final _recorder = AudioRecorder();
  final _queue = RecordingUploadQueue.instance;

  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  DateTime _lastActivityAt = DateTime.now();
  Timer? _inactivityChecker;
  Timer? _ticker;

  // --- текущая сессия
  String? _sessionId;
  String _token = '';
  DateTime? _startedAt;
  int _chunkBytes = 0;
  int _nextSeq = 0;
  int _totalBytes = 0;
  String? _cartId;
  int _chunkSeconds = RecordingConfig.defaultChunkSeconds;
  bool _starting = false;

  // --- контекст консультации для 4sell: этап и версии полей анкеты
  String? _stage;
  final Map<String, int> _fieldVersions = {};
  final Map<String, Object?> _fieldValues = {};
  final Map<String, String?> _fieldValueLabels = {};
  bool _stopping = false;

  // --- поток и нарезка
  StreamSubscription<Uint8List>? _sub;
  Completer<void>? _streamDone;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  /// Время первого записанного сэмпла консультации. Начало каждого куска =
  /// _audioStartAt + длительность уже нарезанного звука. Так метки идут
  /// ровно встык (кусок N+1 начинается там, где кончился N) и не «пляшут»
  /// от того, пачками ли микрофон отдаёт байты.
  DateTime? _audioStartAt;
  Future<void> _writeChain = Future.value();

  /// ID текущей сессии — он же ORIGIN_ID лида. null, если запись не идёт.
  String? get currentCommunicationId => isRecording.value ? _sessionId : null;

  /// Корзина, к которой сейчас относится запись.
  String? get recordingCartId => isRecording.value ? _cartId : null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  void _onGlobalPointerEvent(PointerEvent event) {
    _lastActivityAt = DateTime.now();
  }

  Future<void> _checkInactivity() async {
    if (!isRecording.value) return;
    if (DateTime.now().difference(_lastActivityAt) < RecordingConfig.inactivityTimeout) return;
    debugPrint('CallRecordingService: 30 минут без активности — останавливаю запись');
    await stop(reason: 'timeout');
  }

  // ===================================================================
  // Старт / стоп
  // ===================================================================

  /// Запускает новую сессию. Возвращает true, если запись начал именно
  /// этот вызов (false — уже шла, нет разрешения или ошибка).
  ///
  /// [trigger]: button | lead_form | bad_lead_form | bottom_menu | checkout
  Future<bool> start({required String trigger, String? cartId}) async {
    if (isRecording.value || _starting) return false;
    _starting = true;
    try {
      if (!await _recorder.hasPermission()) return false;

      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token') ?? '';
      final seconds = await RecordingConfig.chunkSeconds();
      _chunkSeconds = seconds;
      _chunkBytes = seconds * RecordingConfig.bytesPerSecond;
      _sessionId = newUuidV4();
      _startedAt = DateTime.now();
      _nextSeq = 0;
      _totalBytes = 0;
      _cartId = cartId;
      _buf.clear();
      _audioStartAt = null;
      _lastActivityAt = DateTime.now();

      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: RecordingConfig.sampleRate,
        numChannels: RecordingConfig.numChannels,
      ));
      _streamDone = Completer<void>();
      _sub = stream.listen(
        _onPcm,
        onError: (Object e) {
          debugPrint('CallRecordingService: ошибка потока микрофона ($e)');
          unawaited(stop(reason: 'error'));
        },
        onDone: () {
          if (!(_streamDone?.isCompleted ?? true)) _streamDone!.complete();
        },
        cancelOnError: false,
      );

      isRecording.value = true;
      elapsed.value = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final s = _startedAt;
        if (s != null) elapsed.value = DateTime.now().difference(s);
      });
      await _saveActive();

      await _sendSessionStarted(trigger: trigger);
      return true;
    } catch (e) {
      debugPrint('CallRecordingService.start: $e');
      try { await _recorder.stop(); } catch (_) {}
      await _resetState();
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<void> _sendSessionStarted({required String trigger, String? previousSessionId}) async {
    final customer = await CustomerStorage.loadActive();
    await _event('session_started', {
      'trigger': trigger,
      'site': 'svet',
      'platform': Platform.operatingSystem,
      'manager': {
        'id': (await CustomerStorage.currentManagerId())?.toString(),
        'name': await CustomerStorage.currentManagerName(),
        'email': await CustomerStorage.currentManagerEmail(),
      },
      'audio': {
        'format': 'wav',
        'encoding': 'pcm_s16le',
        'sample_rate': RecordingConfig.sampleRate,
        'channels': RecordingConfig.numChannels,
        'chunk_seconds': _chunkSeconds,
      },
      if (previousSessionId != null) 'previous_session_id': previousSessionId,
      if (_cartId != null) 'cart_id': _cartId,
      // Клиент, выбранный на момент старта (с кнопки внизу — обычно
      // уже есть; из анкеты — ещё нет, придёт событием lead_created).
      if (_cartId != null && customer != null) 'client': _clientJson(customer),
    });
  }

  /// Автостарт при открытии анкеты. true — запись начала анкета (тогда при
  /// закрытии без отправки анкета сама её остановит).
  Future<bool> startForLeadForm({bool badLead = false}) =>
      start(trigger: badLead ? 'bad_lead_form' : 'lead_form');

  /// Останавливает запись: дописывает хвост последним куском и отправляет
  /// session_ended. Возвращает ID завершённой сессии.
  ///
  /// [reason]: manual | order | order_queued | timeout | bad_lead |
  /// lead_form_closed | error
  Future<String?> stop({String reason = 'manual'}) async {
    if (!isRecording.value || _stopping) return null;
    _stopping = true;
    final sessionId = _sessionId;
    try {
      _ticker?.cancel();
      try {
        await _recorder.stop();
      } catch (e) {
        debugPrint('CallRecordingService.stop: $e');
      }
      // Ждём, пока поток отдаст последние байты.
      try {
        await _streamDone?.future.timeout(const Duration(seconds: 2));
      } catch (_) {}
      await _sub?.cancel();
      _sub = null;

      final tail = _buf.takeBytes();
      final minTail = RecordingConfig.bytesPerSecond * RecordingConfig.minTail.inMilliseconds ~/ 1000;
      if (tail.length >= minTail || (_nextSeq == 0 && tail.isNotEmpty)) {
        _emitChunk(tail.length.isOdd ? tail.sublist(0, tail.length - 1) : tail);
      }
      await _writeChain;

      final durationMs = _totalBytes * 1000 ~/ RecordingConfig.bytesPerSecond;
      await _event('session_ended', {
        'reason': reason,
        'last_seq': _nextSeq - 1,
        'chunks': _nextSeq,
        'duration_ms': durationMs,
        if (_cartId != null) 'cart_id': _cartId,
        if (_stage != null) 'stage': _stage,
      });
      return sessionId;
    } finally {
      await _resetState();
      _stopping = false;
    }
  }

  Future<void> _resetState() async {
    _ticker?.cancel();
    await _sub?.cancel();
    _sub = null;
    _buf.clear();
    _sessionId = null;
    _startedAt = null;
    _cartId = null;
    _nextSeq = 0;
    _totalBytes = 0;
    _audioStartAt = null;
    _stage = null;
    _fieldVersions.clear();
    _fieldValues.clear();
    _fieldValueLabels.clear();
    isRecording.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }

  // ===================================================================
  // Нарезка
  // ===================================================================

  void _onPcm(Uint8List data) {
    if (data.isEmpty || _sessionId == null) return;
    if (_audioStartAt == null) {
      // Первый звук консультации: сейчас минус длительность пришедших байт.
      final ms = data.length * 1000 ~/ RecordingConfig.bytesPerSecond;
      _audioStartAt = DateTime.now().subtract(Duration(milliseconds: ms));
    }
    _buf.add(data);
    while (_buf.length >= _chunkBytes) {
      final all = _buf.takeBytes();
      _emitChunk(Uint8List.sublistView(all, 0, _chunkBytes));
      if (all.length > _chunkBytes) {
        final rest = Uint8List.fromList(Uint8List.sublistView(all, _chunkBytes));
        _buf.add(rest);
      }
    }
  }

  void _emitChunk(Uint8List pcm) {
    final sessionId = _sessionId;
    if (sessionId == null || pcm.isEmpty) return;
    final seq = _nextSeq++;
    final base = _audioStartAt ?? DateTime.now();
    final startedAt = base.add(Duration(
        milliseconds: _totalBytes * 1000 ~/ RecordingConfig.bytesPerSecond));
    _totalBytes += pcm.length;
    final durationMs = pcm.length * 1000 ~/ RecordingConfig.bytesPerSecond;
    final token = _token;
    final cartId = _cartId;
    final stage = _stage;
    final fragmentId = newUuidV4();
    final bytes = Uint8List.fromList(pcm); // своя копия — буфер переиспользуется

    // Запись файлов строго по очереди, чтобы seq уходили по порядку.
    _writeChain = _writeChain.then((_) async {
      try {
        final path = await _queue.chunkPath(sessionId, seq);
        final f = File(path);
        final sink = f.openWrite();
        sink.add(_wavHeader(bytes.length));
        sink.add(bytes);
        await sink.close();
        await _queue.add(RecordingJob(
          id: '$sessionId:$seq',
          kind: 'chunk',
          sessionId: sessionId,
          token: token,
          at: startedAt,
          seq: seq,
          durationMs: durationMs,
          filePath: path,
          fragmentId: fragmentId,
          cartId: cartId,
          stage: stage,
        ));
        await _saveActive();
      } catch (e) {
        debugPrint('CallRecordingService: не удалось сохранить кусок $seq ($e)');
      }
    });
  }

  static Uint8List _wavHeader(int dataSize) {
    const rate = RecordingConfig.sampleRate;
    const ch = RecordingConfig.numChannels;
    const bps = RecordingConfig.bytesPerSample;
    final b = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < 4; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }
    str(0, 'RIFF');
    b.setUint32(4, 36 + dataSize, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, ch, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * ch * bps, Endian.little);
    b.setUint16(32, ch * bps, Endian.little);
    b.setUint16(34, bps * 8, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataSize, Endian.little);
    return b.buffer.asUint8List();
  }

  // ===================================================================
  // События — к чему относится разговор
  // ===================================================================

  Future<void> _event(String type, Map<String, dynamic> data, {String? sessionId, String? token}) async {
    final sid = sessionId ?? _sessionId;
    if (sid == null) return;
    var tok = token ?? (sid == _sessionId ? _token : '');
    if (tok.isEmpty) {
      tok = (await SharedPreferences.getInstance()).getString('auth_token') ?? '';
    }
    final at = DateTime.now();
    // Событие встаёт в очередь после уже нарезанных кусков.
    await _writeChain;
    await _queue.add(RecordingJob(
      id: newUuidV4(),
      kind: 'event',
      sessionId: sid,
      token: tok,
      at: at,
      type: type,
      data: data,
    ));
  }

  Map<String, dynamic> _clientJson(Customer c) => {
        'is_company': c.isCompany,
        if (c.contactId != null) 'contact_id': c.contactId,
        if (c.companyId != null) 'company_id': c.companyId,
        if (c.leadId != null) 'lead_id': c.leadId,
        if (c.potentialDealId != null) 'potential_deal_id': c.potentialDealId,
        if (c.potentialDealTitle != null) 'potential_deal_title': c.potentialDealTitle,
      };

  /// Лид создан. [sessionId] — для лидов из фоновой очереди, когда
  /// запись к этому моменту уже могла закончиться.
  Future<void> onLeadCreated({
    required String leadId,
    String? contactId,
    String kind = 'lead',
    String? sessionId,
  }) =>
      _event('lead_created', {
        'lead_id': leadId,
        if (contactId != null) 'contact_id': contactId,
        'kind': kind,
      }, sessionId: sessionId);

  /// В анкете выбран уже существующий клиент вместо создания нового.
  Future<void> onClientSelected(Customer customer) async {
    if (!isRecording.value) return;
    await _event('client_selected', _clientJson(customer));
  }

  /// Вызывать после смены активной корзины (и после setActive клиента).
  ///
  /// - Первая корзина за сессию — привязка (basket_active).
  /// - Другая корзина посреди записи — другой покупатель: по требованию
  ///   4sell один кусок не должен смешивать двух покупателей. Текущий кусок
  ///   обрезается и уходит в прежнюю консультацию, она закрывается
  ///   (reason=cart_switched), и тут же, без паузы в записи, начинается
  ///   новая консультация для новой корзины.
  Future<void> onActiveCartChanged(String newCartId) async {
    if (!isRecording.value || newCartId == _cartId || _stopping) return;
    if (_cartId == null) {
      _cartId = newCartId;
      await _saveActive();
      final customer = await CustomerStorage.loadActive();
      await _event('basket_active', {
        'cart_id': newCartId,
        if (customer != null) 'client': _clientJson(customer),
      });
      return;
    }
    await _rotateSession(newCartId);
  }

  Future<void> _rotateSession(String newCartId) async {
    final oldId = _sessionId;
    if (oldId == null) return;
    final oldCart = _cartId;
    final oldStage = _stage;

    // Синхронно (без await) — чтобы ни один байт из микрофона не попал
    // между обрезкой куска и сменой ID: дальше _onPcm пишет в новую сессию.
    final tail = _buf.takeBytes();
    if (tail.isNotEmpty) {
      _emitChunk(tail.length.isOdd ? tail.sublist(0, tail.length - 1) : tail);
    }
    final lastSeq = _nextSeq - 1;
    final chunks = _nextSeq;
    final durationMs = _totalBytes * 1000 ~/ RecordingConfig.bytesPerSecond;
    // Новая консультация продолжает ту же звуковую дорожку без паузы.
    if (_audioStartAt != null) {
      _audioStartAt = _audioStartAt!.add(Duration(milliseconds: durationMs));
    }

    _sessionId = newUuidV4();
    _startedAt = DateTime.now();
    _nextSeq = 0;
    _totalBytes = 0;
    _cartId = newCartId;
    // Экран при смене корзины не меняется — этап переносим в новую
    // консультацию, чтобы её первые куски не уходили без этапа.
    _stage = oldStage;
    _fieldVersions.clear();
    _fieldValues.clear();
    _fieldValueLabels.clear();
    elapsed.value = Duration.zero;

    await _event('session_ended', {
      'reason': 'cart_switched',
      'last_seq': lastSeq,
      'chunks': chunks,
      'duration_ms': durationMs,
      if (oldCart != null) 'cart_id': oldCart,
      if (oldStage != null) 'stage': oldStage,
      'next_session_id': _sessionId,
    }, sessionId: oldId);
    await _saveActive();
    await _sendSessionStarted(trigger: 'cart_switch', previousSessionId: oldId);
    if (oldStage != null) {
      await _event('stage_changed', {'stage': oldStage, 'reason': 'cart_switch'});
    }
  }

  // ===================================================================
  // Этап консультации и действия менеджера (контекст для 4sell)
  // ===================================================================

  static const stageClientData = 'client_data'; // 1. Данные клиента
  static const stageNeeds = 'needs';            // 2. Выявление потребности
  static const stageCatalog = 'catalog';        // 3. Работа с каталогом
  static const stageCart = 'cart';              // 4. Корзина
  static const stageCheckout = 'checkout';      // оформление заказа

  String? get currentStage => isRecording.value ? _stage : null;

  /// Этап консультации изменён (событие stage_changed).
  Future<void> setStage(String stage, {String? reason}) async {
    if (!isRecording.value) return;
    // Запись начата кнопкой без корзины, а менеджер уже работает с корзиной
    // (открыл её или оформление) — привязываем текущую. Тогда последующая
    // смена корзины корректно разделит консультацию, а не просто привяжет.
    if (_cartId == null && (stage == stageCart || stage == stageCheckout)) {
      final active = await CustomerStorage.getActiveCartId();
      if (active != null && active.isNotEmpty) await onActiveCartChanged(active);
    }
    if (_stage == stage) return;
    final prev = _stage;
    _stage = stage;
    await _event('stage_changed', {
      'stage': stage,
      if (prev != null) 'previous_stage': prev,
      if (reason != null) 'reason': reason,
    });
  }

  /// Открыт раздел каталога — по нему 4sell решает, каких полей не хватает
  /// для подбора (подсказки 3.1–3.5).
  Future<void> onCatalogSectionOpened({required String sectionId, required String sectionName}) async {
    if (!isRecording.value) return;
    await setStage(stageCatalog, reason: 'section_opened');
    await _event('catalog_section_opened', {
      'section_id': sectionId,
      'section_name': sectionName,
      if (_cartId != null) 'cart_id': _cartId,
    });
  }

  /// Товар добавлен в корзину.
  Future<void> onProductAdded({
    required String cartId,
    required String productId,
    required String productName,
    required int quantity,
  }) async {
    if (!isRecording.value) return;
    if (_cartId == null) await onActiveCartChanged(cartId);
    await _event('product_added', {
      'cart_id': cartId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
    });
  }

  /// Поле анкеты изменено. [source]: manager (ввёл/исправил вручную) |
  /// manager_confirmed (подтвердил предложенное) | auto (автозаполнение).
  /// Версия поля растёт на каждое изменение в пределах консультации —
  /// по ней 4sell понимает, что значение уже правил менеджер.
  Future<void> onFieldChanged({
    required String field,
    required Object? value,
    String? label,
    String? valueLabel,
    String source = 'manager',
  }) async {
    if (!isRecording.value) return;
    final prev = _fieldValues[field];
    final prevLabel = _fieldValueLabels[field];
    final version = (_fieldVersions[field] ?? 0) + 1;
    _fieldVersions[field] = version;
    _fieldValues[field] = value;
    _fieldValueLabels[field] = valueLabel;
    await _event('field_changed', {
      'field': field,
      if (label != null) 'label': label,
      'value': value,
      if (valueLabel != null) 'value_label': valueLabel,
      'previous_value': prev,
      if (prevLabel != null) 'previous_value_label': prevLabel,
      'source': source,
      'version': version,
      'author': {
        'id': (await CustomerStorage.currentManagerId())?.toString(),
        'name': await CustomerStorage.currentManagerName(),
      },
    });
  }

  /// Заказ из корзины [cartId] создан на сервере. Если запись относится к
  /// этой корзине (или ещё ни к какой) — событие + остановка.
  /// Возвращает ID сессии, к которой привязан заказ (для deal_found).
  Future<String?> onOrderCreated({required String cartId, required String orderId}) async {
    if (!isRecording.value) return null;
    if (_cartId != null && _cartId != cartId) return null;
    _cartId ??= cartId;
    await _event('order_created', {'order_id': orderId, 'cart_id': cartId});
    return stop(reason: 'order');
  }

  /// Нет интернета — заказ лёг в офлайн-очередь, номера ещё нет.
  Future<void> onOrderQueued({required String cartId}) async {
    if (!isRecording.value) return;
    if (_cartId != null && _cartId != cartId) return;
    _cartId ??= cartId;
    await _event('order_queued', {'cart_id': cartId});
    await stop(reason: 'order_queued');
  }

  /// Сделка в Битрикс24 найдена по номеру заказа (создаётся с задержкой).
  Future<void> onDealFound({required String sessionId, required String orderId, required String dealId}) =>
      _event('deal_found', {'order_id': orderId, 'deal_id': dealId}, sessionId: sessionId);

  // ===================================================================
  // Восстановление после убитого приложения
  // ===================================================================

  Future<void> _saveActive() async {
    final sid = _sessionId;
    if (sid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, jsonEncode({
      'id': sid,
      'token': _token,
      'nextSeq': _nextSeq,
      'totalBytes': _totalBytes,
      'cartId': _cartId,
    }));
  }

  /// Вызывать при старте приложения ПОСЛЕ RecordingUploadQueue.restore():
  /// если прошлую запись оборвало закрытие приложения — закрываем сессию.
  Future<void> recoverInterruptedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeKey);
    if (raw == null) return;
    await prefs.remove(_activeKey);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final next = j['nextSeq'] as int? ?? 0;
      await _event('session_ended', {
        'reason': 'app_restarted',
        'last_seq': next - 1,
        'chunks': next,
        'duration_ms': (j['totalBytes'] as int? ?? 0) * 1000 ~/ RecordingConfig.bytesPerSecond,
        if (j['cartId'] != null) 'cart_id': j['cartId'],
      }, sessionId: j['id'] as String, token: j['token'] as String?);
    } catch (e) {
      debugPrint('CallRecordingService.recover: $e');
    }
  }

  void dispose() {
    _ticker?.cancel();
    _inactivityChecker?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    _recorder.dispose();
  }
}
