import 'package:shared_preferences/shared_preferences.dart';

/// Настройки непрерывной записи разговора кусками.
///
/// Сейчас куски уходят в тестовый приёмник на prons.kz
/// (/ajax/offlinesvet/rec_test/rec.php). Когда 4sell пришлёт новый
/// endpoint и ключ — меняется только RecordingApi / этот адрес, сама
/// запись, нарезка и очередь остаются как есть.
class RecordingConfig {
  RecordingConfig._();

  static const String endpoint = String.fromEnvironment(
    'REC_ENDPOINT',
    defaultValue: 'https://prons.kz/ajax/offlinesvet/rec_test/rec.php',
  );

  /// Длина куска по умолчанию. Сервер возвращает актуальное значение в
  /// ответ на session_started — оно запоминается и применяется со
  /// следующей записи (5/10/15 с меняются без новой сборки).
  static const int defaultChunkSeconds =
      int.fromEnvironment('REC_CHUNK_SECONDS', defaultValue: 10);

  /// WAV PCM 16-bit моно. 48 кГц — родной формат 4sell (≈0,94 МБ на 10 с).
  static const int sampleRate =
      int.fromEnvironment('REC_SAMPLE_RATE', defaultValue: 48000);
  static const int numChannels = 1;
  static const int bytesPerSample = 2;
  static int get bytesPerSecond => sampleRate * numChannels * bytesPerSample;

  /// Остановка, если в приложении полчаса не было ни одного касания.
  static const Duration inactivityTimeout = Duration(minutes: 30);

  /// Хвост короче этого при остановке не отправляем (щелчок кнопки).
  static const Duration minTail = Duration(milliseconds: 500);

  static const _chunkKey = 'rec_chunk_seconds';

  static Future<int> chunkSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_chunkKey) ?? defaultChunkSeconds;
    return v.clamp(3, 60);
  }

  static Future<void> saveServerChunkSeconds(int seconds) async {
    if (seconds < 3 || seconds > 60) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chunkKey, seconds);
  }
}
