import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/customer/models/customer_model.dart';

/// Базовый URL входящего вебхука Bitrix24.
const String _bitrixWebhookUrl =
    'https://abis.bitrix24.kz/rest/21537/l7qiphejvc8khwx7';

/// ID enum-значений справочника UF_CRM_1544076714 ("Тип клиента (СВЕТ)")
const _typeFieldCode = 'UF_CRM_1544076714';

/// ID enum-значений справочника UF_CRM_1673861444
/// ("Источник клиента для САЛОНОВ Света 2026")
const _sourceFieldCode = 'UF_CRM_1673861444';

/// ID значения "Другое" — источник по умолчанию, если менеджер не указал.
const String defaultSourceId = '76585';

/// Полный список значений источника для UI (dropdown), id -> название.
const Map<String, String> leadSources = {
  '35313': 'Существующий клиент',
  '100519': '2ГИС',
  '35315': 'Витрина',
  '78677': 'Сертификат, полученный от партнера',
  '35319': 'По рекомендации',
  '78703': 'Instagram',
  '35321': 'По рекомендации партнера или дизайнера',
  '45343': 'Центр Красок #1',
  '78683': 'Таргетинг (реклама с Instagram)',
  '79745': 'Выставка',
  '79747': 'Контекстная реклама',
  '79749': 'Маркетплейс (Каспи/Халык)',
  '35323': 'Интернет-магазин svet.kz',
  '78013': 'Запрос на почту',
  '100695': 'Мастер-класс (мероприятие)',
  '76585': 'Другое',
};

// -------------------------------------------------------
// Поля для формы "Некачественный лид" — та же общая CRM, что и у красок
// (коды и ID значений сверены через crm.lead.fields напрямую в Bitrix24,
// а не переиспользованы из формы красок — там для части полей отдельные
// коды с пометкой "(КРАСКИ)"). Взяты версии "(СВЕТ)" там, где они есть
// отдельно (Пол, Психотип) — по аналогии с _typeFieldCode выше, который
// тоже "(СВЕТ)", а не "(КРАСКИ)".
// -------------------------------------------------------

/// "Сколько человек было с клиентом" — одиночный выбор.
const _peopleCountFieldCode = 'UF_CRM_1636358700';
const Map<String, String> peopleCountOptions = {
  '79087': 'Сам клиент',
  '13621': '1 (один)',
  '13623': '2 (два)',
  '13625': '3 (три)',
  '13627': '4 (четыре)',
  '13629': '5 (пять)',
  '13631': '6 (шесть)',
  '14105': 'Семья',
};
/// Если выбрано это значение — поле "Кто был с клиентом" не нужно (сам
/// клиент, больше некому быть) — так же скрывается и на сайте.
const String peopleCountAloneId = '79087';

/// "Кто был с клиентом" — множественный выбор, показывается только если
/// peopleCount != peopleCountAloneId.
const _whoWasWithFieldCode = 'UF_CRM_1636547473';
const Map<String, String> whoWasWithOptions = {
  '14107': 'Мужчина',
  '14109': 'Женщина',
  '14111': 'Бабушка',
  '14113': 'Дедушка',
  '14115': 'Ребенок',
  '14117': 'Девушка',
  '14119': 'Парень',
};

/// "Пол клиента" — одиночный выбор.
const _genderFieldCode = 'UF_CRM_1533875517'; // "Пол(СВЕТ)"
const Map<String, String> genderOptions = {
  '210': 'Мужчина',
  '212': 'Женщина',
  '3971': 'Семья',
};

/// "Возраст клиента" — одиночный выбор (общее поле, отдельного "(СВЕТ)" нет).
const _ageFieldCode = 'UF_CRM_1636539997';
const Map<String, String> ageOptions = {
  '14055': '25-35 лет',
  '14057': '35-45 лет',
  '14059': '45-55 лет',
  '14061': '55 и старше',
};

/// "Психотип клиента" — множественный выбор.
const _psychotypeFieldCode = 'UF_CRM_1565330412870'; // "Психотип Клиента (СВЕТ)"
const Map<String, String> psychotypeOptions = {
  '2031': 'Аудиал',
  '2033': 'Визуал',
  '2035': 'Кинестетик',
  '16835': 'Дигитал',
};

/// "Причина провала Лида" — множественный выбор.
const _failReasonFieldCode = 'UF_CRM_1739347472';
const Map<String, String> failReasonOptions = {
  '79113': 'Клиент отказался предоставить данные',
  '79115': 'Отсутствие интереса',
  '79117': 'Нет в ассортименте',
  '79119': 'Дорого (цену озвучил)',
  '79121': 'Не готов к покупкам',
  '79123': 'Просто интересовался',
};

/// Статус лида "Некачественный лид" — системное поле STATUS_ID (не
/// кастомное UF_CRM_...), сверено через crm.status.list.
const String badLeadStatusId = 'JUNK';

/// Исключение — нет подключения к интернету. Отдельный тип, чтобы UI
/// мог показать именно "Нет интернета", а не общую ошибку сети.
class NoInternetException implements Exception {
  @override
  String toString() => 'Нет подключения к интернету';
}

/// Исключение — ошибка ответа Bitrix (например, неверный вебхук, нет прав).
class BitrixApiException implements Exception {
  final String message;
  BitrixApiException(this.message);

  @override
  String toString() => message;
}

class BitrixService {
  BitrixService({required this.dio});

  final Dio dio;

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _requireInternet() async {
    if (!await _hasInternet()) {
      throw NoInternetException();
    }
  }

  Map<String, dynamic> _unwrapResult(Response response) {
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw BitrixApiException('Некорректный ответ сервера Bitrix');
    }
    if (data['error'] != null) {
      final description = data['error_description'] ?? data['error'];
      throw BitrixApiException('Bitrix: $description');
    }
    return data;
  }

  // -------------------------------------------------------
  // Контакты
  // -------------------------------------------------------

  /// Поиск контактов по телефону.
  ///
  /// ВАЖНО: Bitrix не поддерживает LIKE/%-фильтр для мультиполей (PHONE,
  /// EMAIL и т.д.) — фильтрация по ним работает только на точное
  /// совпадение, а точная запись номера в CRM может отличаться форматом
  /// (+7 / 8 / пробелы / скобки). Поэтому ищем правильным способом:
  /// 1) crm.duplicate.findbycomm — он сам нормализует номер и возвращает
  ///    ID совпавших контактов;
  /// 2) crm.contact.list с фильтром по точному ID, чтобы получить карточки.
  Future<List<CustomerSearchResult>> searchContactsByPhone(
    String phone,
  ) async {
    await _requireInternet();

    try {
      final dupResponse = await dio.post(
        '$_bitrixWebhookUrl/crm.duplicate.findbycomm.json',
        data: {
          'type': 'PHONE',
          'values': [phone],
        },
      );

      final dupData = _unwrapResult(dupResponse);

      // Bitrix возвращает result как объект {"CONTACT":[...], "LEAD":[...]}
      // когда есть хотя бы одно совпадение, но как ПУСТОЙ СПИСОК []
      // когда совпадений вообще нет ни по одной сущности. Поэтому нельзя
      // жёстко кастовать в Map — нужно сначала проверить тип.
      final rawDupResult = dupData['result'];
      final dupResult = rawDupResult is Map<String, dynamic>
          ? rawDupResult
          : <String, dynamic>{};

      final contactIds = (dupResult['CONTACT'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      if (contactIds.isEmpty) return [];

      final listResponse = await dio.post(
        '$_bitrixWebhookUrl/crm.contact.list.json',
        data: {
          'filter': {'ID': contactIds},
          'select': ['ID', 'NAME', 'LAST_NAME', 'PHONE'],
        },
      );

      final listData = _unwrapResult(listResponse);
      final result = listData['result'] as List<dynamic>? ?? [];

      return result.map((e) {
        final item = e as Map<String, dynamic>;
        final phones = item['PHONE'] as List<dynamic>? ?? [];
        final phoneValue = phones.isNotEmpty
            ? (phones.first as Map<String, dynamic>)['VALUE']?.toString() ?? ''
            : '';

        return CustomerSearchResult(
          contactId: item['ID'].toString(),
          name: item['NAME']?.toString() ?? '',
          lastName: item['LAST_NAME']?.toString() ?? '',
          phone: phoneValue,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('searchContactsByPhone: ошибка сети: $e');
      throw BitrixApiException('Ошибка соединения с Bitrix');
    }
  }

  /// Создаёт новый контакт. Возвращает ID созданного контакта.
  Future<String> createContact({
    required String name,
    String lastName = '',
    required String phone,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.contact.add.json',
        data: {
          'fields': {
            'NAME': name,
            'LAST_NAME': lastName,
            'PHONE': [
              {'VALUE': phone, 'VALUE_TYPE': 'WORK'},
            ],
          },
        },
      );

      final data = _unwrapResult(response);
      return data['result'].toString();
    } on DioException catch (e) {
      debugPrint('createContact: ошибка сети: $e');
      throw BitrixApiException('Не удалось создать контакт в Bitrix');
    }
  }

  // -------------------------------------------------------
  // Лиды
  // -------------------------------------------------------

  /// Ищет пользователя Bitrix24 по ФИО — нужен, потому что user_id менеджера
  /// в приложении берётся из другой системы (prons.kz, 1C-Bitrix) и НЕ
  /// совпадает с ID того же человека в Bitrix24 (два разных продукта,
  /// независимая нумерация пользователей). Возвращает null, если совпадений
  /// нет или их несколько (чтобы не назначить лид не тому человеку наугад).
  ///
  /// ВАЖНО: user_name хранится строкой вида "Фамилия Имя" (например,
  /// "Леготкин Максим"), а в самом Bitrix24 это два ОТДЕЛЬНЫХ поля (NAME,
  /// LAST_NAME) — такая же точная строка "Леготкин Максим" нигде в
  /// профиле не хранится целиком, поэтому широкий FILTER[FIND] по всей
  /// строке её не находит. Разбиваем на слова и ищем прицельно по полям.
  Future<int?> findUserIdByName(String fullName) async {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    // user_name хранится как "Фамилия Имя" — для обычного случая (без
    // отчества) это ровно два слова.
    if (parts.length == 2) {
      final byOrder1 = await _findUserId(lastName: parts[0], name: parts[1]);
      if (byOrder1 != null) return byOrder1;
      // На случай если где-то ФИО сохранено в обратном порядке ("Имя Фамилия").
      final byOrder2 = await _findUserId(lastName: parts[1], name: parts[0]);
      if (byOrder2 != null) return byOrder2;
    }

    // Запасной вариант (три и более слова — с отчеством, или одно слово) —
    // широкий поиск по всей строке через user.search.
    return _findUserIdByFind(fullName);
  }

  Future<int?> _findUserId({required String lastName, required String name}) async {
    try {
      final response = await dio.get(
        '$_bitrixWebhookUrl/user.get.json',
        queryParameters: {
          'FILTER[NAME]': name,
          'FILTER[LAST_NAME]': lastName,
        },
      );
      final data = _unwrapResult(response);
      final results = data['result'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      if (results.length > 1) {
        debugPrint('findUserIdByName: неоднозначно — найдено ${results.length} '
            'пользователей Bitrix24 по имени "$name $lastName", пропускаю ASSIGNED_BY_ID');
        return null;
      }
      final id = results.first['ID'];
      return int.tryParse(id.toString());
    } catch (e) {
      debugPrint('findUserIdByName: ошибка user.get ($e)');
      return null;
    }
  }

  Future<int?> _findUserIdByFind(String fullName) async {
    try {
      final response = await dio.get(
        '$_bitrixWebhookUrl/user.search.json',
        queryParameters: {'FILTER[FIND]': fullName},
      );
      final data = _unwrapResult(response);
      final results = data['result'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        debugPrint('findUserIdByName: пользователь Bitrix24 не найден по имени "$fullName"');
        return null;
      }
      if (results.length > 1) {
        debugPrint('findUserIdByName: неоднозначно — найдено ${results.length} '
            'пользователей Bitrix24 по имени "$fullName", пропускаю ASSIGNED_BY_ID');
        return null;
      }
      final id = results.first['ID'];
      return int.tryParse(id.toString());
    } catch (e) {
      debugPrint('findUserIdByName: ошибка user.search ($e)');
      return null;
    }
  }

  /// Создаёт лид, привязанный к контакту. Возвращает ID созданного лида.
  Future<String> createLead({
    required String contactId,
    required String name,
    required String phone,
    required CustomerType type,
    String comment = '',
    String sourceId = defaultSourceId,
    int? managerId,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.lead.add.json',
        data: {
          'fields': {
            'TITLE': 'Новый клиент (приложение): $name',
            'NAME': name,
            'PHONE': [
              {'VALUE': phone, 'VALUE_TYPE': 'WORK'},
            ],
            'COMMENTS': comment,
            'CONTACT_ID': contactId,
            _typeFieldCode: type.bitrixFieldId,
            _sourceFieldCode: [sourceId],
            // Без этого поля Bitrix назначает ответственным того, на кого
            // настроен сам вебхук — а не менеджера, который реально
            // авторизован в приложении и создал лид.
            if (managerId != null) 'ASSIGNED_BY_ID': managerId,
          },
        },
      );

      final data = _unwrapResult(response);
      final leadId = data['result'].toString();

      // Запоминаем ID только что созданного лида — отдельная кнопка
      // "Записать разговор" (вне анкеты) использует это значение, чтобы
      // прикрепить запись именно к этому лиду, даже если запись
      // закончится позже, чем сохранится сама анкета.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_lead_id', leadId);
      await prefs.setInt('last_lead_created_at', DateTime.now().millisecondsSinceEpoch);

      return leadId;
    } on DioException catch (e) {
      debugPrint('createLead: ошибка сети: $e');
      throw BitrixApiException('Не удалось создать лид в Bitrix');
    }
  }

  /// "Некачественный лид" — отдельная короткая анкета для случаев, когда
  /// сделка не состоялась (клиент отказался от общения, ушёл без покупки
  /// и т.п.). В отличие от createLead(), НЕ создаёт контакт и не требует
  /// имя/телефон — сайт тоже не спрашивает контактные данные на этом
  /// сценарии (одна из причин провала — "Клиент отказался предоставить
  /// данные"). STATUS_ID выставляется сразу в "Некачественный лид"
  /// (badLeadStatusId) и в самой форме не выбирается.
  Future<String> createBadLead({
    String? title,
    String comment = '',
    String? peopleCount,
    List<String> whoWasWith = const [],
    String? gender,
    String? age,
    List<String> psychotype = const [],
    List<String> failReasons = const [],
    int? managerId,
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.lead.add.json',
        data: {
          'fields': {
            'TITLE': (title != null && title.isNotEmpty) ? title : 'Некачественный лид (приложение)',
            'STATUS_ID': badLeadStatusId,
            'COMMENTS': comment,
            // Без этого поля Bitrix назначает ответственным того, на кого
            // настроен сам вебхук — а не менеджера, который реально
            // авторизован в приложении и создал лид.
            if (managerId != null) 'ASSIGNED_BY_ID': managerId,
            if (peopleCount != null) _peopleCountFieldCode: peopleCount,
            if (whoWasWith.isNotEmpty) _whoWasWithFieldCode: whoWasWith,
            if (gender != null) _genderFieldCode: gender,
            if (age != null) _ageFieldCode: age,
            if (psychotype.isNotEmpty) _psychotypeFieldCode: psychotype,
            if (failReasons.isNotEmpty) _failReasonFieldCode: failReasons,
          },
        },
      );

      final data = _unwrapResult(response);
      final leadId = data['result'].toString();

      // Та же логика, что и в createLead() — чтобы кнопка "Записать
      // разговор" могла прикрепить запись именно к этому лиду.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_lead_id', leadId);
      await prefs.setInt('last_lead_created_at', DateTime.now().millisecondsSinceEpoch);

      return leadId;
    } on DioException catch (e) {
      debugPrint('createBadLead: ошибка сети: $e');
      throw BitrixApiException('Не удалось создать лид в Bitrix');
    }
  }

  /// Последний созданный лид (для привязки записи разговора). Возвращает
  /// null, если лида ещё не было или он был создан слишком давно
  /// (maxAge) — на случай если менеджер забыл остановить старую запись.
  static Future<String?> getLastLeadId({Duration maxAge = const Duration(hours: 3)}) async {
    final prefs = await SharedPreferences.getInstance();
    final leadId = prefs.getString('last_lead_id');
    final createdAtMs = prefs.getInt('last_lead_created_at');
    if (leadId == null || createdAtMs == null) return null;

    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    if (DateTime.now().difference(createdAt) > maxAge) return null;

    return leadId;
  }

  // -------------------------------------------------------
  // Запись разговора
  // -------------------------------------------------------

  /// Прикрепляет аудиофайл записи разговора как комментарий с файлом
  /// к указанному лиду (crm.timeline.comment.add с полем FILES).
  /// Хранения записей на сервере сайта нет — файл целиком уходит в Bitrix.
  Future<void> attachRecordingToLead({
    required String leadId,
    required String base64Content,
    required String filename,
    String comment = 'Запись разговора с клиентом (из мобильного приложения)',
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.timeline.comment.add.json',
        data: {
          'fields': {
            'ENTITY_ID': leadId,
            'ENTITY_TYPE': 'lead',
            'COMMENT': comment,
            'FILES': [
              [filename, base64Content],
            ],
          },
        },
      );

      _unwrapResult(response);
    } on DioException catch (e) {
      debugPrint('attachRecordingToLead: ошибка сети: $e');
      throw BitrixApiException('Не удалось прикрепить запись к лиду в Bitrix');
    }
  }

  // ПОДТВЕРЖДЕНО: поле ORIGIN_ID — стандартное системное поле Bitrix,
  // предназначенное именно для этого сценария (хранит ID записи из
  // внешней системы, из которой была создана сделка — в вашем случае
  // это номер заказа на сайте). Проверено на реальной сделке (ID 385919):
  // ORIGIN_ID там равен номеру заказа "100097", как и ожидалось.
  static const _dealOrderNumberFieldCode = 'ORIGIN_ID';

  /// Ищет сделку (Deal) по номеру заказа на сайте — сделка создаётся
  /// автоматически при оформлении заказа через create_order.php, и в
  /// её карточке номер заказа хранится отдельным полем (подтверждено
  /// скриншотом карточки сделки в Bitrix24: "Номер заказа: 100097").
  /// Это точное совпадение, а не эвристика "самая свежая сделка" —
  /// надёжнее для привязки записи разговора именно к нужной сделке.
  Future<String?> findDealByOrderNumber(String orderId) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.deal.list.json',
        data: {
          'filter': {_dealOrderNumberFieldCode: orderId},
          'select': ['ID'],
        },
      );

      final data = _unwrapResult(response);
      final result = data['result'];
      if (result is List && result.isNotEmpty) {
        return result.first['ID'].toString();
      }
      return null;
    } on DioException catch (e) {
      debugPrint('findDealByOrderNumber: ошибка сети: $e');
      return null;
    }
  }

  /// Прикрепляет аудиофайл записи разговора как комментарий с файлом
  /// к указанной сделке (та же логика, что attachRecordingToLead, но
  /// для сделки, а не лида).
  Future<void> attachRecordingToDeal({
    required String dealId,
    required String base64Content,
    required String filename,
    String comment = 'Запись разговора с клиентом (из мобильного приложения)',
  }) async {
    await _requireInternet();

    try {
      final response = await dio.post(
        '$_bitrixWebhookUrl/crm.timeline.comment.add.json',
        data: {
          'fields': {
            'ENTITY_ID': dealId,
            'ENTITY_TYPE': 'deal',
            'COMMENT': comment,
            'FILES': [
              [filename, base64Content],
            ],
          },
        },
      );

      _unwrapResult(response);
    } on DioException catch (e) {
      debugPrint('attachRecordingToDeal: ошибка сети: $e');
      throw BitrixApiException('Не удалось прикрепить запись к сделке в Bitrix');
    }
  }
}
