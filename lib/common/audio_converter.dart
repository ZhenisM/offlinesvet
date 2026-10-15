import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Сжатие записи разговора WAV → M4A (AAC, по умолчанию 64 кбит/с) для
/// вложения в Битрикс24 — встроенными средствами телефона (Android
/// MediaCodec / iOS AVFoundation, см. MainActivity.kt и AppDelegate.swift).
/// В 4sell по-прежнему уходит исходный WAV.
class AudioConverter {
  static const _channel = MethodChannel('kz.svet.offline/audio');

  /// Возвращает путь к M4A или null, если сжать не удалось (тогда
  /// вызывающий код использует WAV как раньше).
  static Future<String?> wavToM4a(String wavPath, {int bitrate = 64000}) async {
    final out = '${wavPath.replaceAll(RegExp(r'\.wav$', caseSensitive: false), '')}.m4a';
    try {
      return await _channel.invokeMethod<String>('wavToM4a', {'input': wavPath, 'output': out, 'bitrate': bitrate});
    } catch (e) {
      debugPrint('AudioConverter: $e');
      return null;
    }
  }
}
