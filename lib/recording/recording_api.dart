import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:offlinesvet/recording/recording_config.dart';

/// Ошибка отправки. permanent = повторять бессмысленно (кривые данные),
/// иначе — сеть/сервер/токен, очередь повторит позже.
class RecordingApiException implements Exception {
  final String message;
  final bool permanent;
  final int? status;
  RecordingApiException(this.message, {this.permanent = false, this.status});
  @override
  String toString() => 'RecordingApiException($status): $message';
}

/// HTTP-клиент приёмника записи. Сейчас — тестовый rec.php на prons.kz.
class RecordingApi {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
  ));

  static String _ts(DateTime d) => d.toUtc().toIso8601String();

  Future<Map<String, dynamic>> sendChunk({
    required String token,
    required String sessionId,
    required int seq,
    required DateTime startedAt,
    required int durationMs,
    required String filePath,
    required String fragmentId,
    String? cartId,
    String? stage,
  }) {
    return _post(FormData.fromMap({
      'token': token,
      'action': 'chunk',
      'session_id': sessionId,
      'fragment_id': fragmentId,
      'seq': seq,
      'started_at': _ts(startedAt),
      'ended_at': _ts(startedAt.add(Duration(milliseconds: durationMs))),
      'duration_ms': durationMs,
      if (cartId != null) 'cart_id': cartId,
      if (stage != null) 'stage': stage,
      'audio': MultipartFile.fromFileSync(
        filePath,
        filename: '${sessionId}_$seq.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
    }));
  }

  Future<Map<String, dynamic>> sendEvent({
    required String token,
    required String sessionId,
    required String eventId,
    required String type,
    required DateTime at,
    required Map<String, dynamic> data,
  }) {
    return _post(FormData.fromMap({
      'token': token,
      'action': 'event',
      'session_id': sessionId,
      'event_id': eventId,
      'type': type,
      'at': _ts(at),
      'data': jsonEncode(data),
    }));
  }

  Future<Map<String, dynamic>> _post(FormData form) async {
    final Response<String> r;
    try {
      r = await _dio.post<String>(RecordingConfig.endpoint, data: form);
    } on DioException catch (e) {
      throw RecordingApiException('Сеть: ${e.type.name} ${e.message ?? ''}');
    }
    final code = r.statusCode ?? 0;
    Map<String, dynamic> body = {};
    try {
      final j = jsonDecode(r.data ?? '');
      if (j is Map<String, dynamic>) body = j;
    } catch (_) {}

    if (code == 200 && body['ok'] == true) return body;
    if (code == 409) return body; // уже принято — считаем успехом

    final msg = body['error']?.toString() ?? 'HTTP $code';
    // 400/403/404/413/422 — данные не примут и при повторе.
    // 401 (токен) и 5xx — временное, повторяем.
    final permanent = const {400, 403, 404, 405, 413, 422}.contains(code);
    throw RecordingApiException(msg, permanent: permanent, status: code);
  }
}
