import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart';

/// Синглтон, который владеет самой записью разговора. Раньше это жило
/// внутри State виджета на главном экране — и при переходе в каталог
/// после сохранения анкеты экран (а с ним и State, и сам AudioRecorder)
/// уничтожался, обрывая запись. Синглтон не привязан к экрану вообще —
/// живёт всё время работы приложения, поэтому переживает любые переходы.
class CallRecordingService {
  CallRecordingService._();
  static final CallRecordingService instance = CallRecordingService._();

  final _recorder = AudioRecorder();
  final _bitrixService = BitrixService(dio: Dio());

  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  Timer? _ticker;
  String? _currentFilePath;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (isRecording.value) return; // уже пишем — повторный старт игнорируем

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

  /// Просто останавливает запись и возвращает путь к файлу, без
  /// прикрепления куда-либо — на случай, если понадобится сделать что-то
  /// своё с файлом (сейчас основной сценарий — stopAndAttachToLead ниже).
  Future<String?> stop() async {
    if (!isRecording.value) return null;
    _ticker?.cancel();
    final path = await _recorder.stop();
    isRecording.value = false;
    return path ?? _currentFilePath;
  }

  /// Останавливает запись (если она идёт) и сразу прикрепляет файл к
  /// указанному лиду. Вызывается из анкеты в момент успешного создания
  /// лида — именно поэтому не нужно отдельно искать "последний лид".
  /// Если запись не была начата — тихо ничего не делает (это нормальный
  /// сценарий: не каждое создание лида сопровождается записью разговора).
  ///
  /// ВАЖНО: если отправка в Bitrix не удалась (нет интернета и т.п.) —
  /// исключение прокидывается вызывающему коду, а временный файл
  /// НЕ удаляется (чтобы запись не потерялась молча). Полноценного
  /// автоматического повтора отправки офлайн-записей пока нет — это
  /// известное ограничение текущей версии, при отсутствии сети запись
  /// нужно будет отправить вручную ещё раз (см. TODO при необходимости
  /// добавить очередь повторных попыток).
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

    // Удаляем временный файл только после успешной отправки.
    try { await File(filePath).delete(); } catch (_) {}
  }

  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
  }
}
