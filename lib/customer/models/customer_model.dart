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

  /// Выбранный «потенциальный проект» — сделка Битрикс24 из поля контакта
  /// UF_CRM_1782219134. Как на сайте: POTENTIAL_DEAL {ID, TITLE} в данных
  /// клиента корзины, при оформлении — свойства заказа 214 и 261.
  final String? potentialDealId;
  final String? potentialDealTitle;

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
    this.potentialDealId,
    this.potentialDealTitle,
  });

  String get fullName =>
      lastName.isEmpty ? name : '$name $lastName'.trim();

  /// Уникальный идентификатор для индексации в списке клиентов менеджера
  /// (заменяет старый contactId-only ключ — работает для обоих типов).
  String get storageKey => isCompany ? 'company_$companyId' : 'contact_$contactId';

  /// Сериализация в формат UF_MULTIBASKETS_CLIENT_INFO для HL-блока
  /// Multibaskets (cart_save.php, action=create).
  ///
  /// В отличие от формата на сайте (который иногда пишет урезанный JSON
  /// без ENTITY/ID для клиентов без ещё созданного контакта — там лид
  /// создаётся раньше контакта), наше приложение всегда уже имеет
  /// contactId/companyId к моменту создания корзины, поэтому всегда
  /// пишем полный формат с ENTITY/ID/TYPE_ID — это сохраняет прямую
  /// ссылку на CRM-сущность для будущих этапов (оформление заказа и т.д.)
  Map<String, dynamic> toMultibasketsClientInfo() {
    if (isCompany) {
      return {
        'ENTITY': 'COMPANY',
        'ID': companyId,
        'TITLE': name,
        'BIN': bin,
      };
    }
    return {
      'ENTITY': 'CONTACT',
      'ID': contactId,
      'TYPE_ID': type.bitrixFieldId,
      'TYPE': type.label,
      'NAME': fullName,
      'PHONE': phone,
      'COMPANY_BIN': null,
      // Тот же формат, что пишет сайт (SvetApp\Client\Contact::setCurrent).
      if (potentialDealId != null && potentialDealId!.isNotEmpty)
        'POTENTIAL_DEAL': {'ID': potentialDealId, 'TITLE': potentialDealTitle ?? ''},
    };
  }

  /// Обратное восстановление Customer из clientInfo, как он приходит от
  /// cart_load.php. Используется при переключении текущей корзины на
  /// экране мультикорзины — чтобы синхронизировать CustomerStorage
  /// (главный экран показывает того же клиента, что и активная корзина).
  ///
  /// Это приложение всегда пишет в Multibaskets полный формат
  /// (ENTITY/ID/TYPE_ID), но на всякий случай не падает, если встретится
  /// урезанный формат с сайта — просто восстановит частичные данные.
  static Customer fromMultibasketsClientInfo(
    Map<String, dynamic> clientInfo, {
    required DateTime selectedAt,
  }) {
    final entity = clientInfo['ENTITY']?.toString();
    final isCompanyEntity = entity == 'COMPANY';

    if (isCompanyEntity) {
      return Customer(
        companyId: clientInfo['ID']?.toString(),
        isCompany: true,
        name: clientInfo['TITLE']?.toString() ?? '',
        bin: clientInfo['BIN']?.toString() ?? '',
        type: CustomerType.client,
        selectedAt: selectedAt,
      );
    }

    final typeId = clientInfo['TYPE_ID']?.toString();
    final type = typeId == CustomerType.designer.bitrixFieldId
        ? CustomerType.designer
        : CustomerType.client;

    final deal = potentialDealOf(clientInfo);
    return Customer(
      contactId: clientInfo['ID']?.toString(),
      isCompany: false,
      name: clientInfo['NAME']?.toString() ?? '',
      phone: clientInfo['PHONE']?.toString() ?? '',
      type: type,
      selectedAt: selectedAt,
      potentialDealId: deal?.id,
      potentialDealTitle: deal?.title,
    );
  }

  /// Проект из данных клиента корзины. Сайт пишет вложенный объект
  /// POTENTIAL_DEAL {ID, TITLE}; на всякий случай понимаем и плоские
  /// POTENTIAL_DEAL_ID / POTENTIAL_DEAL_TITLE. null — проект не выбран.
  static PotentialDeal? potentialDealOf(Map<String, dynamic>? clientInfo) {
    if (clientInfo == null) return null;
    String id = '';
    String title = '';
    final nested = clientInfo['POTENTIAL_DEAL'];
    if (nested is Map) {
      id = nested['ID']?.toString() ?? '';
      title = nested['TITLE']?.toString() ?? '';
    }
    if (id.isEmpty) {
      id = clientInfo['POTENTIAL_DEAL_ID']?.toString() ?? '';
      title = clientInfo['POTENTIAL_DEAL_TITLE']?.toString() ?? title;
    }
    if (id.isEmpty || id == 'null') return null;
    return PotentialDeal(id: id, title: title);
  }

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
    String? potentialDealId,
    String? potentialDealTitle,
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
      potentialDealId: potentialDealId ?? this.potentialDealId,
      potentialDealTitle: potentialDealTitle ?? this.potentialDealTitle,
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
        'potentialDealId': potentialDealId,
        'potentialDealTitle': potentialDealTitle,
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
      potentialDealId: json['potentialDealId']?.toString(),
      potentialDealTitle: json['potentialDealTitle']?.toString(),
    );
  }
}

/// Потенциальный проект контакта — сделка Битрикс24 (ID + заголовок,
/// например «ЖК Эстет - 70м²»).
class PotentialDeal {
  final String id;
  final String title;
  const PotentialDeal({required this.id, required this.title});
}

/// Результат поиска контакта в Bitrix (короткая карточка для списка выбора).
class CustomerSearchResult {
  final String contactId;
  final String name;
  final String lastName;
  final String phone;
  final CustomerType type;

  /// Потенциальные проекты из поля контакта UF_CRM_1782219134.
  final List<PotentialDeal> potentialDeals;

  const CustomerSearchResult({
    required this.contactId,
    required this.name,
    this.lastName = '',
    required this.phone,
    this.type = CustomerType.client,
    this.potentialDeals = const [],
  });

  String get fullName => lastName.isEmpty ? name : '$name $lastName'.trim();
}

/// Результат поиска компании в Highload-блоке CompanyList (ID=30, prons.kz).
class CompanySearchResult {
  final String companyId;
  final String name;
  final String fullName;
  final String bin;
  final String phone;
  final String email;

  const CompanySearchResult({
    required this.companyId,
    required this.name,
    this.fullName = '',
    required this.bin,
    this.phone = '',
    this.email = '',
  });
}
