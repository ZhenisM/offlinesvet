import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart';

/// Синглтон, который владеет самой записью разговора. Раньше это жило
/// внутри State виджета на главном экране — и при переходе в каталог
/// после сохранения анкеты экран (а с ним и State, и сам AudioRecorder)
/// уничтожался, обрывая запись. Синглтон не привязан к экрану вообще —
/// живёт всё время работы приложения, поэтому переживает любые переходы.
///
/// Поддерживает два сценария:
/// 1. Запись под анкету лида — start() + stopAndAttachToLead(leadId).
/// 2. Запись под корзину (кнопка в нижней панели) — startForCart(cartId).
///    Если менеджер переключит активную корзину, пока идёт запись —
///    она останавливается и "откладывается" именно за ТУ корзину, за
///    которую шла (onActiveCartChanged). Отложенная запись лежит на
///    устройстве, пока корзину не оформят в заказ — тогда
///    attachPendingRecordingForCart() отправляет её в сделку, созданную
///    для этого заказа.
class CallRecordingService {
  CallRecordingService._() {
    // Ловит АБСОЛЮТНО ЛЮБОЕ касание где угодно в приложении, независимо
    // от того, какой сейчас экран — не нужно ничего добавлять в main.dart
    // или в отдельные экраны, чтобы отслеживать активность пользователя.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);

    // Раз в 30 секунд проверяем: если идёт запись и уже 10+ минут не было
    // вообще никакого взаимодействия с приложением — останавливаем её
    // автоматически (защита на случай, если менеджер забыл остановить
    // запись вручную и ушёл).
    _inactivityChecker = Timer.periodic(const Duration(seconds: 30), (_) => _checkInactivity());
  }

  static final CallRecordingService instance = CallRecordingService._();

  static const _inactivityTimeout = Duration(minutes: 10);

  DateTime _lastActivityAt = DateTime.now();
  Timer? _inactivityChecker;

  void _onGlobalPointerEvent(PointerEvent event) {
    _lastActivityAt = DateTime.now();
  }

  Future<void> _checkInactivity() async {
    if (!isRecording.value) return;
    if (DateTime.now().difference(_lastActivityAt) < _inactivityTimeout) return;

    debugPrint('CallRecordingService: 10 минут без активности — останавливаю запись автоматически');

    if (_recordingCartId != null) {
      // Запись за корзину — сохраняем как отложенную, как при обычной
      // остановке (ничего не теряем, отправится при оформлении заказа).
      await _stopAndStashForCart(_recordingCartId!);
    } else {
      // Запись под анкету лида, которая ещё не была отправлена — тут
      // отдавать файл некуда (лида пока нет), поэтому просто
      // останавливаем. Кнопка в интерфейсе сама отреагирует на
      // isRecording = false.
      await stop();
    }
  }

  final _recorder = AudioRecorder();
  final _bitrixService = BitrixService(dio: Dio());

  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  Timer? _ticker;
  String? _currentFilePath;

  /// ID корзины, за которую сейчас идёт запись — null, если текущая
  /// запись не привязана к корзине (например, идёт под анкету лида).
  String? _recordingCartId;

  /// ID корзины, за которую сейчас идёт запись (null, если запись не
  /// привязана к корзине — например, идёт под анкету лида).
  String? get recordingCartId => _recordingCartId;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> _startInternal() async {
    _lastActivityAt = DateTime.now();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

    _currentFilePath = path;
    elapsed.value = Duration.zero;
    isRecording.value = true;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed.value += const Duration(seconds: 1);
    });
  }

  /// Запись без привязки к корзине (сценарий анкеты лида).
  Future<void> start() async {
    if (isRecording.value) return; // уже пишем — повторный старт игнорируем
    _recordingCartId = null;
    await _startInternal();
  }

  /// Запись, привязанная к конкретной корзине (кнопка в нижней панели).
  Future<void> startForCart(String cartId) async {
    if (isRecording.value) return;
    _recordingCartId = cartId;
    await _startInternal();
  }

  /// Просто останавливает запись и возвращает путь к файлу, без
  /// прикрепления/сохранения куда-либо.
  Future<String?> stop() async {
    if (!isRecording.value) return null;
    _ticker?.cancel();
    final path = await _recorder.stop();
    isRecording.value = false;
    final result = path ?? _currentFilePath;
    _recordingCartId = null;
    return result;
  }

  // -------------------------------------------------------
  // Сценарий "лид"
  // -------------------------------------------------------

  /// Останавливает запись (если она идёт) и сразу прикрепляет файл к
  /// указанному лиду. Вызывается из анкеты в момент успешного создания
  /// лида. Если записи не было — тихо ничего не делает.
  ///
  /// ВАЖНО: если отправка в Bitrix не удалась (нет интернета и т.п.) —
  /// исключение прокидывается вызывающему коду, а временный файл
  /// НЕ удаляется (чтобы запись не потерялась молча).
  Future<void> stopAndAttachToLead(String leadId) async {
    if (!isRecording.value) return;

    final filePath = await stop();
    if (filePath == null) return;

    final bytes = await File(filePath).readAsBytes();
    final base64Content = base64Encode(bytes);
    final filename = 'call_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _bitrixService.attachRecordingToLead(
      leadId: leadId,
      base64Content: base64Content,
      filename: filename,
    );

    try { await File(filePath).delete(); } catch (_) {}
  }

  // -------------------------------------------------------
  // Сценарий "корзина -> сделка"
  // -------------------------------------------------------

  static String _pendingKey(String cartId) => 'pending_cart_recording_$cartId';

  /// Вызывать при переключении активной корзины (в любом месте, где это
  /// происходит — переключатель корзин и т.п.). Если в этот момент шла
  /// запись за ДРУГУЮ корзину — останавливает её и откладывает именно за
  /// ту (прежнюю) корзину, к которой она относилась. Если запись шла уже
  /// за newCartId (или не шла вообще) — ничего не делает.
  Future<void> onActiveCartChanged(String newCartId) async {
    if (!isRecording.value) return;
    final oldCartId = _recordingCartId;
    if (oldCartId == null || oldCartId == newCartId) return;
    await _stopAndStashForCart(oldCartId);
  }

  /// Ручная остановка кнопкой в нижней панели (не переключением корзины).
  /// Тоже "откладывает" запись за текущую корзину — сделки может ещё не
  /// быть, пока заказ не оформлен, поэтому сразу никуда не отправляем.
  Future<void> stopRecordingForCart() async {
    if (!isRecording.value) return;
    final cartId = _recordingCartId;
    if (cartId == null) { await stop(); return; }
    await _stopAndStashForCart(cartId);
  }

  Future<void> _stopAndStashForCart(String cartId) async {
    final path = await stop();
    if (path == null) return;

    final prefs = await SharedPreferences.getInstance();
    // Если у этой корзины уже была отложенная запись (например, запись
    // включали/выключали несколько раз для одного и того же разговора) —
    // старый файл больше не нужен, новый его заменяет.
    final oldPath = prefs.getString(_pendingKey(cartId));
    if (oldPath != null && oldPath != path) {
      try { await File(oldPath).delete(); } catch (_) {}
    }
    await prefs.setString(_pendingKey(cartId), path);
  }

  /// Есть ли отложенная (ещё не отправленная) запись для этой корзины.
  Future<bool> hasPendingRecordingForCart(String cartId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pendingKey(cartId));
  }

  /// Вызывать сразу после успешного оформления заказа из этой корзины,
  /// когда уже известен ID созданной сделки. Если для корзины есть
  /// отложенная запись — отправляет её в комментарии сделки и убирает
  /// из отложенных. Если записи не было — тихо ничего не делает.
  Future<void> attachPendingRecordingForCart(String cartId, String dealId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _pendingKey(cartId);
    final path = prefs.getString(key);
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) {
      await prefs.remove(key);
      return;
    }

    final bytes = await file.readAsBytes();
    final base64Content = base64Encode(bytes);
    final filename = 'call_cart${cartId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _bitrixService.attachRecordingToDeal(
      dealId: dealId,
      base64Content: base64Content,
      filename: filename,
    );

    await prefs.remove(key);
    try { await file.delete(); } catch (_) {}
  }

  void dispose() {
    _ticker?.cancel();
    _inactivityChecker?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    _recorder.dispose();
  }
}
