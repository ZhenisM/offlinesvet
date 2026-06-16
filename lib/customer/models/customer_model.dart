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

/// Выбранный менеджером клиент — физлицо (контакт Bitrix) либо компания
/// (запись из Highload-блока CompanyList на prons.kz).
///
/// Поля выровнены с форматом JSON "Данные клиента" в HL-блоке Multibaskets
/// (ID=25 на prons.kz), чтобы при будущей интеграции корзины не пришлось
/// менять модель — только добавить cartItems.
class Customer {
  /// ID контакта в Bitrix24 CRM. Заполнен только если isCompany == false.
  final String? contactId;

  /// ID компании в HL-блоке CompanyList (prons.kz). Заполнен только если
  /// isCompany == true.
  final String? companyId;

  final bool isCompany;

  final String? leadId; // null, если выбран уже существующий клиент/компания
  final String name;
  final String lastName;
  final String phone;
  final String email;
  final String bin; // БИН/ИИН — заполнен только для компаний
  final CustomerType type;
  final DateTime selectedAt;

  const Customer({
    this.contactId,
    this.companyId,
    this.isCompany = false,
    this.leadId,
    required this.name,
    this.lastName = '',
    this.phone = '',
    this.email = '',
    this.bin = '',
    required this.type,
    required this.selectedAt,
  });

  String get fullName =>
      lastName.isEmpty ? name : '$name $lastName'.trim();

  /// Уникальный идентификатор для индексации в списке клиентов менеджера
  /// (заменяет старый contactId-only ключ — работает для обоих типов).
  String get storageKey => isCompany ? 'company_$companyId' : 'contact_$contactId';

  Customer copyWith({
    String? contactId,
    String? companyId,
    bool? isCompany,
    String? leadId,
    String? name,
    String? lastName,
    String? phone,
    String? email,
    String? bin,
    CustomerType? type,
    DateTime? selectedAt,
  }) {
    return Customer(
      contactId: contactId ?? this.contactId,
      companyId: companyId ?? this.companyId,
      isCompany: isCompany ?? this.isCompany,
      leadId: leadId ?? this.leadId,
      name: name ?? this.name,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      bin: bin ?? this.bin,
      type: type ?? this.type,
      selectedAt: selectedAt ?? this.selectedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'companyId': companyId,
        'isCompany': isCompany,
        'leadId': leadId,
        'name': name,
        'lastName': lastName,
        'phone': phone,
        'email': email,
        'bin': bin,
        'type': type.name,
        'selectedAt': selectedAt.toIso8601String(),
      };

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      contactId: json['contactId']?.toString(),
      companyId: json['companyId']?.toString(),
      isCompany: json['isCompany'] == true,
      leadId: json['leadId']?.toString(),
      name: json['name']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      bin: json['bin']?.toString() ?? '',
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

/// Результат поиска компании в Highload-блоке CompanyList (ID=30, prons.kz).
class CompanySearchResult {
  final String companyId;
  final String name;
  final String fullName;
  final String bin;

  const CompanySearchResult({
    required this.companyId,
    required this.name,
    this.fullName = '',
    required this.bin,
  });
}
