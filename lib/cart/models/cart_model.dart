import 'dart:convert';

/// Статус корзины — соответствует enum-полю UF_MULTIBASKETS_STATUS
/// (ID элементов справочника: 137/138/139, подтверждены через
/// debug_status_field.php на стороне сервера).
enum CartStatus {
  inProgress, // "в работе"
  completed, // "оформлена"
  deleted; // "удалена"

  static CartStatus fromLabel(String label) {
    switch (label) {
      case 'оформлена':
        return CartStatus.completed;
      case 'удалена':
        return CartStatus.deleted;
      case 'в работе':
      default:
        return CartStatus.inProgress;
    }
  }

  String get label {
    switch (this) {
      case CartStatus.inProgress:
        return 'в работе';
      case CartStatus.completed:
        return 'оформлена';
      case CartStatus.deleted:
        return 'удалена';
    }
  }
}

/// Один товар в корзине. SELECT_ROOM обязателен — сервер (cart_save.php)
/// отклонит сохранение корзины, если у любого товара это поле пустое.
class CartItem {
  final int productId;
  final int quantity;
  final String selectRoom;
  final String rasprodazha;

  const CartItem({
    required this.productId,
    required this.quantity,
    required this.selectRoom,
    this.rasprodazha = 'Без скидки',
  });

  Map<String, dynamic> toJson() => {
        'PRODUCT_ID': productId,
        'QUANTITY': quantity,
        'PROPS': {
          'SELECT_ROOM': selectRoom,
          '_RASPRODAZHA': rasprodazha,
        },
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final props = json['PROPS'] as Map<String, dynamic>? ?? {};
    return CartItem(
      productId: (json['PRODUCT_ID'] as num?)?.toInt() ?? 0,
      quantity: (json['QUANTITY'] as num?)?.toInt() ?? 0,
      selectRoom: props['SELECT_ROOM']?.toString() ?? '',
      rasprodazha: props['_RASPRODAZHA']?.toString() ?? 'Без скидки',
    );
  }
}

/// Сериализует список товаров в формат UF_MULTIBASKETS_PRODUCTS_INFO —
/// строка из " / "-разделённых JSON-объектов (это НЕ единый JSON-массив,
/// такой нестандартный формат уже используется на сайте, и cart_save.php
/// его ожидает именно в таком виде).
String encodeCartItems(List<CartItem> items) {
  if (items.isEmpty) return '';
  return items.map((item) => jsonEncode(item.toJson())).join(' / ');
}

/// Разбирает строку UF_MULTIBASKETS_PRODUCTS_INFO обратно в список товаров.
/// Некорректные фрагменты пропускаются молча — частичная порча данных не
/// должна ронять весь экран мультикорзины.
List<CartItem> decodeCartItems(String productsInfo) {
  if (productsInfo.isEmpty) return [];

  final items = <CartItem>[];
  for (final part in productsInfo.split(' / ')) {
    if (part.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(part) as Map<String, dynamic>;
      items.add(CartItem.fromJson(decoded));
    } catch (_) {
      // пропускаем повреждённый фрагмент, не роняем весь парсинг
    }
  }
  return items;
}

/// Корзина — соответствует одной строке HL-блока Multibaskets (ID=25).
/// Каждый выбор/создание клиента менеджером порождает новую корзину
/// (даже для уже существующего клиента) — корзины не переиспользуются.
class Cart {
  final String id;
  final String title;
  final CartStatus status;
  final bool isCurrent;
  final DateTime dateCreate;
  final Map<String, dynamic>? clientInfo;
  final List<CartItem> items;

  const Cart({
    required this.id,
    required this.title,
    required this.status,
    required this.isCurrent,
    required this.dateCreate,
    this.clientInfo,
    this.items = const [],
  });

  int get itemsCount => items.fold(0, (sum, item) => sum + item.quantity);

  Cart copyWith({
    String? id,
    String? title,
    CartStatus? status,
    bool? isCurrent,
    DateTime? dateCreate,
    Map<String, dynamic>? clientInfo,
    List<CartItem>? items,
  }) {
    return Cart(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      isCurrent: isCurrent ?? this.isCurrent,
      dateCreate: dateCreate ?? this.dateCreate,
      clientInfo: clientInfo ?? this.clientInfo,
      items: items ?? this.items,
    );
  }

  factory Cart.fromJson(Map<String, dynamic> json) {
    return Cart(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      status: CartStatus.fromLabel(json['status']?.toString() ?? ''),
      isCurrent: json['isCurrent'] == true,
      dateCreate: _parseDate(json['dateCreate']?.toString() ?? ''),
      clientInfo: json['clientInfo'] as Map<String, dynamic>?,
      items: decodeCartItems(json['productsInfo']?.toString() ?? ''),
    );
  }

  static DateTime _parseDate(String raw) {
    // Формат от сервера: "19.06.2026 10:04:41"
    try {
      final parts = raw.split(' ');
      final dateParts = parts[0].split('.');
      final timeParts =
          parts.length > 1 ? parts[1].split(':') : ['0', '0', '0'];
      return DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        timeParts.length > 2 ? int.parse(timeParts[2]) : 0,
      );
    } catch (_) {
      return DateTime.now();
    }
  }
}
