import 'package:flutter_test/flutter_test.dart';
import 'package:offlinesvet/foursell/foursell_api.dart';

/// Структура payload сверена с openapi.yaml 4sell v1.3.0 (OrderEventDefault).
void main() {
  test('payload DEFAULT: обязательные поля и формат времени', () {
    final p = FourSellApi.buildCreatedPayload(
      orderId: 'c1', eventId: '15830e60-5454-48b0-b51b-79cb4b7fb796',
      startedAt: DateTime.utc(2026, 9, 28, 10), endedAt: DateTime.utc(2026, 9, 28, 10, 3),
      employeeId: '1', formKind: FourSellFormKind.badLead,
    );
    expect(p.keys, containsAll(['event_type', 'sent_at', 'order', 'employee', 'service_window', 'cart', 'meta']));
    expect((p['order'] as Map).keys, containsAll(['order_id', 'point_of_sale_id', 'cashier_desk_id', 'opened_at', 'closed_at']));
    expect((p['cart']['items'] as List), isNotEmpty); // minItems: 1
    expect(p['cart']['items'][0]['product_name'], 'Некачественный лид');
    expect(p['meta']['source_system'], 'DEFAULT');
    expect(p['sent_at'] as String, endsWith('Z'));
    expect(p['service_window']['started_at'], '2026-09-28T10:00:00.000Z');
  });
}
