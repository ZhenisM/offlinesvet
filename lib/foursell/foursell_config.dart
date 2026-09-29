/// Настройки интеграции с 4sell.ai.
///
/// Ключ НЕ хранится в репозитории (он публичный на GitHub) — передаётся
/// при сборке:
///   flutter build apk --dart-define=FOURSELL_API_KEY=xxxx
/// В GitHub Actions — через secrets:
///   --dart-define=FOURSELL_API_KEY=${{ secrets.FOURSELL_API_KEY }}
/// Если ключ не передан, интеграция тихо выключена (записи в Bitrix
/// продолжают уходить как раньше, в 4sell — ничего).
class FourSellConfig {
  FourSellConfig._();

  static const String apiKey = String.fromEnvironment('FOURSELL_API_KEY');

  /// Боевой адрес, выданный 4sell (в их openapi.yaml был шаблонный
  /// integration-api.4sell.ai — такого домена нет в DNS).
  static const String baseUrl = String.fromEnvironment(
    'FOURSELL_BASE_URL',
    defaultValue: 'https://integration-api.k1.4sell.ai',
  );

  static const String apiPrefix = '/api/v1/integration';

  static bool get isEnabled => apiKey.isNotEmpty;

  /// Обязательные поля их схемы DEFAULT. У нас не касса — ставим
  /// фиксированные значения, пока 4sell не скажет, что туда писать.
  static const String pointOfSaleId =
      String.fromEnvironment('FOURSELL_POS_ID', defaultValue: 'offlinesvet');
  static const String cashierDeskId =
      String.fromEnvironment('FOURSELL_DESK_ID', defaultValue: 'mobile-app');

  /// meta.source_version — обязателен в схеме DEFAULT.
  static const String sourceVersion = '1.0.0';

  /// PCM 16-bit × 48 кГц × моно.
  static const int wavBytesPerSecond = 48000 * 2 * 1;

  /// cart.items в схеме DEFAULT обязателен и не может быть пустым, а
  /// корзины на момент анкеты нет — шлём одну служебную позицию
  /// с ценой 0. Согласовать с 4sell, что их аналитике это подходит.
  static const String leadFormProductId = 'offlinesvet-lead-form';
  static const String badLeadFormProductId = 'offlinesvet-bad-lead-form';

  /// Метка внешней системы в стандартном поле лида Bitrix ORIGINATOR_ID.
  /// В паре с ORIGIN_ID = ID коммуникации однозначно связывает лид с
  /// записью в 4sell (и по нему можно фильтровать crm.lead.list).
  static const String bitrixOriginatorId = '4sell';
}
