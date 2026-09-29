import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:offlinesvet/foursell/foursell_config.dart';

/// Ошибка, которую бессмысленно повторять (4xx кроме 401/409/429 —
/// по их README: "на 4xx — исправлять данные, повтор не поможет").
/// Очередь такие задачи помечает "failed", а не шлёт бесконечно.
class FourSellPermanentException implements Exception {
  final int? statusCode;
  final String message;
  FourSellPermanentException(this.statusCode, this.message);
  @override
  String toString() => 'FourSell $statusCode: $message';
}

/// Вид анкеты — уходит в 4sell как название единственной позиции
/// корзины (у них cart.items обязателен и minItems: 1, а корзины на
/// момент анкеты у нас нет).
enum FourSellFormKind { lead, badLead }

/// Клиент 4sell Integration API, схема payload DEFAULT
/// (openapi.yaml v1.3.0: OrderEventDefault / OrderRefDefault /
/// EmployeeRefDefault / CartSnapshotDefault / MetaDefault).
/// Везде additionalProperties: false — лишних полей слать нельзя.
class FourSellApi {
  FourSellApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: FourSellConfig.baseUrl + FourSellConfig.apiPrefix,
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(minutes: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'X-API-Key': FourSellConfig.apiKey,
                // Laravel без этого отвечает на ошибки HTML-страницей, а не
                // JSON с message/errors — в логах не видно причины 422.
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;

  /// RFC3339 в UTC с суффиксом Z (обязателен по спецификации).
  static String _ts(DateTime d) => d.toUtc().toIso8601String();

  /// Длительность WAV по размеру: PCM16 48 кГц моно = 96 000 байт/с,
  /// заголовок 44 байта. Для не-WAV — по окну записи.
  static Future<int> _durationMs(String path, DateTime start, DateTime end) async {
    if (path.toLowerCase().endsWith('.wav')) {
      final bytes = await File(path).length();
      final ms = ((bytes - 44) * 1000) ~/ (FourSellConfig.wavBytesPerSecond);
      if (ms > 0) return ms;
    }
    final ms = end.difference(start).inMilliseconds;
    return ms > 0 ? ms : 1;
  }

  static String _contentType(String path) =>
      path.toLowerCase().endsWith('.wav') ? 'audio/wav' : 'audio/mp4';

  /// Собирает payload event_type=created. Вынесено отдельно, чтобы его
  /// можно было проверить против схемы без сети.
  static Map<String, dynamic> buildCreatedPayload({
    required String orderId,
    required String eventId,
    required DateTime startedAt,
    required DateTime endedAt,
    required String employeeId,
    String? employeeName,
    required FourSellFormKind formKind,
    Map<String, dynamic>? audioMeta,
    DateTime? sentAt,
  }) =>
      {
        'event_type': 'created',
        'event_id': eventId,
        'sent_at': _ts(sentAt ?? DateTime.now()),
        'order': {
          'order_id': orderId,
          'opened_at': _ts(startedAt),
          'closed_at': _ts(endedAt),
          'point_of_sale_id': FourSellConfig.pointOfSaleId,
          'cashier_desk_id': FourSellConfig.cashierDeskId,
        },
        'employee': {
          'employee_id': employeeId,
          if (employeeName != null && employeeName.isNotEmpty) 'employee_name': employeeName,
        },
        'service_window': {
          'started_at': _ts(startedAt),
          'ended_at': _ts(endedAt),
        },
        'cart': {
          'currency': 'KZT',
          'items': [
            {
              'product_id': formKind == FourSellFormKind.lead
                  ? FourSellConfig.leadFormProductId
                  : FourSellConfig.badLeadFormProductId,
              'product_name': formKind == FourSellFormKind.lead
                  ? 'Анкета лида'
                  : 'Некачественный лид',
              'quantity': 1,
              'unit_price': 0,
            },
          ],
        },
        if (audioMeta != null) 'audio_meta': audioMeta,
        'meta': {
          'source_system': 'DEFAULT',
          'source_version': FourSellConfig.sourceVersion,
        },
      };

  /// POST /order-events — событие created ВМЕСТЕ с аудио одним
  /// запросом (README 2.1: audio_file опционален в этом же multipart).
  /// Так нет гонки "created ещё не обработан → 404 на загрузке аудио".
  Future<void> sendCreatedWithAudio({
    required String orderId,
    required String eventId,
    required DateTime startedAt,
    required DateTime endedAt,
    required String employeeId,
    String? employeeName,
    required FourSellFormKind formKind,
    String? audioPath,
  }) async {
    Map<String, dynamic>? audioMeta;
    MultipartFile? audioPart;
    if (audioPath != null) {
      if (!await File(audioPath).exists()) {
        throw FourSellPermanentException(null, 'Файл записи не найден: $audioPath');
      }
      final fileName = 'call_$orderId.${audioPath.split('.').last}';
      audioMeta = {
        'file_name': fileName,
        'content_type': _contentType(audioPath),
        'duration_ms': await _durationMs(audioPath, startedAt, endedAt),
      };
      final ct = _contentType(audioPath).split('/');
      audioPart = await MultipartFile.fromFile(
        audioPath,
        filename: fileName,
        contentType: DioMediaType(ct[0], ct[1]),
      );
    }

    final payload = buildCreatedPayload(
      orderId: orderId,
      eventId: eventId,
      startedAt: startedAt,
      endedAt: endedAt,
      employeeId: employeeId,
      employeeName: employeeName,
      formKind: formKind,
      audioMeta: audioMeta,
    );

    final form = FormData();
    // payload — ТЕКСТОВАЯ часть с Content-Type: application/json (без
    // filename, иначе сервер примет её за файл).
    form.files.add(MapEntry(
      'payload',
      MultipartFile.fromString(jsonEncode(payload),
          contentType: DioMediaType('application', 'json')),
    ));
    if (audioPart != null) form.files.add(MapEntry('audio_file', audioPart));

    await _post('/order-events', form, idempotencyKey: eventId);
  }

  /// POST /orders/{order_id}/audio — пригодится для кусков по 10 с.
  /// Сейчас не используется: всё уходит одним запросом выше.
  Future<void> uploadAudio({
    required String orderId,
    required String audioPath,
    required DateTime startedAt,
    required DateTime endedAt,
    required String idempotencyKey,
  }) async {
    final fileName = 'call_$orderId.${audioPath.split('.').last}';
    final ct = _contentType(audioPath).split('/');
    final form = FormData();
    form.files.add(MapEntry(
      'audio_file',
      await MultipartFile.fromFile(audioPath,
          filename: fileName, contentType: DioMediaType(ct[0], ct[1])),
    ));
    form.files.add(MapEntry(
      'audio_meta',
      MultipartFile.fromString(
        jsonEncode({
          'file_name': fileName,
          'content_type': _contentType(audioPath),
          'duration_ms': await _durationMs(audioPath, startedAt, endedAt),
        }),
        contentType: DioMediaType('application', 'json'),
      ),
    ));
    await _post('/orders/$orderId/audio', form, idempotencyKey: idempotencyKey);
  }

  Future<void> _post(String path, FormData form, {required String idempotencyKey}) async {
    try {
      await _dio.post(path, data: form,
          options: Options(headers: {'Idempotency-Key': idempotencyKey}));
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 409) return; // дубликат — уже принято, повторять не нужно
      final body = e.response?.data?.toString() ?? e.message ?? '';
      // Повторяем: сеть/таймаут, 401 (ключ могут починить), 429, 5xx.
      if (code != null && code >= 400 && code < 500 && code != 401 && code != 429) {
        throw FourSellPermanentException(code, '$path: $body');
      }
      rethrow;
    }
  }
}
