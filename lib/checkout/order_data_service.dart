import 'dart:convert';
import 'package:dio/dio.dart';

/// Данные одного варианта свойства (ENUM)
class PropVariant {
  final String value;
  final String name;
  const PropVariant({required this.value, required this.name});

  factory PropVariant.fromJson(Map<String, dynamic> j) =>
      PropVariant(value: j['value'] as String, name: j['name'] as String);
}

/// Служба доставки
class DeliveryService {
  final int id;
  final String name;
  final String description;
  const DeliveryService({
    required this.id,
    required this.name,
    required this.description,
  });

  factory DeliveryService.fromJson(Map<String, dynamic> j) => DeliveryService(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
      );
}

/// Доп. услуга службы доставки (зона, подуслуга)
class DeliveryExtraService {
  final int id;
  final String name;
  final double price;
  const DeliveryExtraService({
    required this.id,
    required this.name,
    required this.price,
  });

  factory DeliveryExtraService.fromJson(Map<String, dynamic> j) =>
      DeliveryExtraService(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        price: (j['price'] as num?)?.toDouble() ?? 0,
      );
}

/// Все данные для экрана оформления заказа
class OrderData {
  final List<DeliveryService> deliveries;
  final Map<int, List<DeliveryExtraService>> deliveryExtras;
  final Map<int, List<PropVariant>> propVariants;

  const OrderData({
    required this.deliveries,
    required this.deliveryExtras,
    required this.propVariants,
  });

  List<PropVariant> variants(int propId) => propVariants[propId] ?? [];
  List<String> variantNames(int propId) =>
      variants(propId).map((v) => v.name).toList();
  List<String> variantValues(int propId) =>
      variants(propId).map((v) => v.value).toList();

  /// Получить value по отображаемому name
  String? valueByName(int propId, String name) {
    final list = variants(propId);
    final found = list.where((v) => v.name == name).firstOrNull;
    return found?.value ?? name; // fallback — передаём name как value
  }

  List<DeliveryExtraService> extrasForDelivery(int deliveryId) =>
      deliveryExtras[deliveryId] ?? [];
}

/// Скрытые свойства заказа менеджера из HL-блока 45.
/// fiz — физ. лицо (обычно), invest — физ. + купон ≥25%, yur — юр. лицо.
class ManagerProps {
  /// Карта propId → value для каждого режима
  final Map<String, String> fiz;
  final Map<String, String> invest;
  final Map<String, String> yur;

  const ManagerProps({
    required this.fiz,
    required this.invest,
    required this.yur,
  });

  static ManagerProps empty() =>
      const ManagerProps(fiz: {}, invest: {}, yur: {});

  factory ManagerProps.fromJson(Map<String, dynamic> j) => ManagerProps(
        fiz:    _parseMap(j['fiz']),
        invest: _parseMap(j['invest']),
        yur:    _parseMap(j['yur']),
      );

  static Map<String, String> _parseMap(dynamic raw) {
    if (raw == null) return {};
    return (raw as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  /// Возвращает нужный набор в зависимости от типа
  Map<String, String> forMode({required bool isLegal, required bool isInvest}) {
    if (isLegal) return yur;
    if (isInvest) return invest;
    return fiz;
  }
}

class OrderDataService {
  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';
  final Dio _dio;

  OrderDataService({Dio? dio}) : _dio = dio ?? Dio();

  Future<ManagerProps> loadManagerProps(int managerId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/get_manager_1c_props.php',
        queryParameters: {'manager_id': managerId},
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      if (json['success'] == true) {
        return ManagerProps.fromJson(json);
      }
    } catch (_) {}
    return ManagerProps.empty();
  }

  Future<OrderData> load() async {
    final response = await _dio.get(
      '$_baseUrl/get_order_data.php',
      options: Options(responseType: ResponseType.plain),
    );

    final json = jsonDecode(response.data as String) as Map<String, dynamic>;

    // Службы доставки
    final deliveries = (json['deliveries'] as List<dynamic>)
        .map((e) => DeliveryService.fromJson(e as Map<String, dynamic>))
        .toList();

    // Доп. услуги по каждой службе
    final Map<int, List<DeliveryExtraService>> deliveryExtras = {};
    final extrasRaw = json['delivery_extra_services'] as Map<String, dynamic>? ?? {};
    for (final entry in extrasRaw.entries) {
      final id = int.tryParse(entry.key);
      if (id == null) continue;
      if (entry.value is! List) continue;
      deliveryExtras[id] = (entry.value as List<dynamic>)
          .map((e) => DeliveryExtraService.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Свойства заказа
    final Map<int, List<PropVariant>> propVariants = {};
    final propsRaw = json['prop_variants'] as Map<String, dynamic>? ?? {};
    for (final entry in propsRaw.entries) {
      final id = int.tryParse(entry.key);
      if (id == null) continue;
      if (entry.value is! List) continue;
      propVariants[id] = (entry.value as List<dynamic>)
          .map((e) => PropVariant.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return OrderData(
      deliveries: deliveries,
      deliveryExtras: deliveryExtras,
      propVariants: propVariants,
    );
  }
}
