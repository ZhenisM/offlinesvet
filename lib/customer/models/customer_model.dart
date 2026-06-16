/// Тип клиента — строго одно из двух значений.
/// Соответствует enum-полю Bitrix UF_CRM_1544076714 ("Тип клиента (СВЕТ)").
enum CustomerType {
  client,
  designer;

  /// ID значения в справочнике Bitrix для поля UF_CRM_1544076714
  String get bitrixFieldId {
    switch (this) {
      case CustomerType.client:
        return '591';
      case CustomerType.designer:
        return '589';
    }
  }

  /// Отображаемое название (используется и как TYPE при будущей записи в HL-блок Multibaskets)
  String get label {
    switch (this) {
      case CustomerType.client:
        return 'Клиент';
      case CustomerType.designer:
        return 'Дизайнер';
    }
  }
}

/// Выбранный менеджером клиент (контакт Bitrix).
///
/// Поля выровнены с форматом JSON "Данные клиента" в HL-блоке Multibaskets
/// (ID=25 на prons.kz), чтобы при будущей интеграции корзины не пришлось
/// менять модель — только добавить cartItems.
class Customer {
  final String contactId;
  final String? leadId; // null, если выбран уже существующий клиент (лид не создавался)
  final String name;
  final String lastName;
  final String phone;
  final String email;
  final CustomerType type;
  final DateTime selectedAt;

  const Customer({
    required this.contactId,
    this.leadId,
    required this.name,
    this.lastName = '',
    required this.phone,
    this.email = '',
    required this.type,
    required this.selectedAt,
  });

  String get fullName =>
      lastName.isEmpty ? name : '$name $lastName'.trim();

  Customer copyWith({
    String? contactId,
    String? leadId,
    String? name,
    String? lastName,
    String? phone,
    String? email,
    CustomerType? type,
    DateTime? selectedAt,
  }) {
    return Customer(
      contactId: contactId ?? this.contactId,
      leadId: leadId ?? this.leadId,
      name: name ?? this.name,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      type: type ?? this.type,
      selectedAt: selectedAt ?? this.selectedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'leadId': leadId,
        'name': name,
        'lastName': lastName,
        'phone': phone,
        'email': email,
        'type': type.name,
        'selectedAt': selectedAt.toIso8601String(),
      };

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      contactId: json['contactId'].toString(),
      leadId: json['leadId']?.toString(),
      name: json['name']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      type: CustomerType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => CustomerType.client,
      ),
      selectedAt: DateTime.tryParse(json['selectedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Результат поиска контакта в Bitrix (короткая карточка для списка выбора).
class CustomerSearchResult {
  final String contactId;
  final String name;
  final String lastName;
  final String phone;

  const CustomerSearchResult({
    required this.contactId,
    required this.name,
    this.lastName = '',
    required this.phone,
  });

  String get fullName => lastName.isEmpty ? name : '$name $lastName'.trim();
}
