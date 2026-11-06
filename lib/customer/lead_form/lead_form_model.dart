import 'package:flutter/foundation.dart';
import 'package:offlinesvet/customer/lead_form/lead_form_options.dart';

/// Помещение анкеты и его поля в лиде Bitrix24 (как в CRM-форме №81).
class LfRoom {
  const LfRoom({
    required this.label,
    required this.sameId,
    required this.diffId,
    required this.height,
    required this.heightCustom,
    required this.area,
    required this.points,
    required this.pointsCustom,
    required this.pointsType,
    required this.style,
  });
  final String label;
  final String sameId;       // значение в «помещения с одинаковой высотой»
  final String diffId;       // значение в «помещения с разной высотой»
  final String height;       // высота потолков (список)
  final String heightCustom; // высота — своё значение (число)
  final String area;         // квадратура
  final String points;       // сколько точек выведено
  final String pointsCustom; // точки — своё значение (число)
  final String pointsType;   // точки под доп. освещение
  final String style;        // стиль помещения
}

const lfRooms = <LfRoom>[
  LfRoom(label: 'Зал', sameId: '17157', diffId: '16867', height: 'UF_CRM_1631877562', heightCustom: 'UF_CRM_1631877596', area: 'UF_CRM_1669800068', points: 'UF_CRM_1636522025', pointsCustom: 'UF_CRM_1636522120', pointsType: 'UF_CRM_1632991487', style: 'UF_CRM_1632990902'),
  LfRoom(label: 'Спальня', sameId: '17159', diffId: '16871', height: 'UF_CRM_1632738818', heightCustom: 'UF_CRM_1632738840', area: 'UF_CRM_1669802292', points: 'UF_CRM_1637222013', pointsCustom: 'UF_CRM_1637232314', pointsType: 'UF_CRM_1637223344', style: 'UF_CRM_1632990960'),
  LfRoom(label: 'Кухня', sameId: '17161', diffId: '16873', height: 'UF_CRM_1631877477', heightCustom: 'UF_CRM_1631877505', area: 'UF_CRM_1669802436', points: 'UF_CRM_1637221967', pointsCustom: 'UF_CRM_1637237372', pointsType: 'UF_CRM_1637223294', style: 'UF_CRM_1632990866'),
  LfRoom(label: 'Дом', sameId: '17163', diffId: '16885', height: 'UF_CRM_1631877234', heightCustom: 'UF_CRM_1631877297', area: 'UF_CRM_1669802534', points: 'UF_CRM_1637221468', pointsCustom: 'UF_CRM_1637232120', pointsType: 'UF_CRM_1637223097', style: 'UF_CRM_1533875314'),
  LfRoom(label: 'Детская', sameId: '17165', diffId: '16887', height: 'UF_CRM_1632738875', heightCustom: 'UF_CRM_1632738894', area: 'UF_CRM_1669802831', points: 'UF_CRM_1637222739', pointsCustom: 'UF_CRM_1637232353', pointsType: 'UF_CRM_1637230159', style: 'UF_CRM_1632990981'),
  LfRoom(label: 'Холл', sameId: '17167', diffId: '16889', height: 'UF_CRM_1632738972', heightCustom: 'UF_CRM_1632738987', area: 'UF_CRM_1669802869', points: 'UF_CRM_1637222835', pointsCustom: 'UF_CRM_1637232174', pointsType: 'UF_CRM_1637231824', style: 'UF_CRM_1632991023'),
  LfRoom(label: 'Коридор', sameId: '17169', diffId: '16891', height: 'UF_CRM_1632738928', heightCustom: 'UF_CRM_1632738944', area: 'UF_CRM_1669802904', points: 'UF_CRM_1637222797', pointsCustom: 'UF_CRM_1637232377', pointsType: 'UF_CRM_1637231772', style: 'UF_CRM_1632990999'),
  LfRoom(label: 'Санузел', sameId: '17171', diffId: '16893', height: 'UF_CRM_1632739025', heightCustom: 'UF_CRM_1632739043', area: 'UF_CRM_1669802938', points: 'UF_CRM_1637222958', pointsCustom: 'UF_CRM_1637232398', pointsType: 'UF_CRM_1637231868', style: 'UF_CRM_1632991043'),
  LfRoom(label: 'Улица', sameId: '17173', diffId: '16895', height: 'UF_CRM_1631877650', heightCustom: 'UF_CRM_1631877676', area: 'UF_CRM_1669803004', points: 'UF_CRM_1637222057', pointsCustom: 'UF_CRM_1637232152', pointsType: 'UF_CRM_1637223399', style: 'UF_CRM_1632990930'),
  LfRoom(label: 'Офис', sameId: '17175', diffId: '16897', height: 'UF_CRM_1631877382', heightCustom: 'UF_CRM_1631877415', area: 'UF_CRM_1669802973', points: 'UF_CRM_1637221833', pointsCustom: 'UF_CRM_1637232221', pointsType: 'UF_CRM_1637223224', style: 'UF_CRM_1632990832'),
  LfRoom(label: 'Прочее', sameId: '17177', diffId: '16899', height: 'UF_CRM_1631877731', heightCustom: 'UF_CRM_1631877760', area: 'UF_CRM_1669802485', points: 'UF_CRM_1637222994', pointsCustom: 'UF_CRM_1637232419', pointsType: 'UF_CRM_1637231915', style: 'UF_CRM_1632991063'),
];

/// Коды полей лида (вне помещений).
class LfF {
  static const gender = 'UF_CRM_1636347555';          // Пол клиента *
  static const sameHeight = 'UF_CRM_1640670449';      // Высота потолков у всех комнат: одинаковая / разная
  static const roomsSame = 'UF_CRM_1640766440';       // помещения с одинаковой высотой (мн.)
  static const roomsDiff = 'UF_CRM_1640601250';       // помещения с разной высотой (мн.)
  static const otherText = 'UF_CRM_1634701837';       // Прочее (своё значение)
  static const heightAll = 'UF_CRM_1640668192';       // высота потолков (общая)
  static const heightAllCustom = 'UF_CRM_1642758257'; // общая высота — своё значение
  static const extraLight = 'UF_CRM_1641293246';      // доп. освещение: есть / нет
  static const styleModeSame = 'UF_CRM_1640692647';   // стиль для комнат (ветка «одинаковая высота»)
  static const styleModeDiff = 'UF_CRM_1642289138';   // стиль для комнат (ветка «разная высота»)
  static const styleAll = 'UF_CRM_1640691645';        // стиль помещения (общий)
  static const source = 'UF_CRM_1673861444';          // Источник клиента для САЛОНОВ Света 2026 *
  static const sourceText = 'UF_CRM_1636538599';      // источник — своё значение
  static const repairStage = 'UF_CRM_1636541019';     // стадия ремонта
  static const age = 'UF_CRM_1636539997';             // возраст *
  static const psychotype = 'UF_CRM_1636540535';      // психотип *
  static const peopleCount = 'UF_CRM_1636358700';     // сколько человек было с клиентом
  static const whoWasWith = 'UF_CRM_1636547473';      // кто был с клиентом (мн.)
  static const category = 'UF_CRM_1771415819';        // категория товара
  // Контакт
  static const coffee = 'UF_CRM_65437F2ED0D00';       // предпочтения клиента (мн.)
  static const iin = 'UF_CRM_1548244582';             // ИИН
}

const lfSourceOther = '76585';  // «Другое» — показываем поле «своё значение»
const lfExtraLightYes = '17219';

/// Подписи «Своё значение» в списках высоты и числа точек.
bool lfIsCustom(String field, String? id) {
  if (id == null) return false;
  final o = leadFormOptions[field]?.where((x) => x.id == id);
  return o != null && o.isNotEmpty && o.first.label.toLowerCase().startsWith('свое');
}

List<LfOption> lfOptions(String field) => leadFormOptions[field] ?? const [];

/// Состояние расширенной анкеты. Собирает поля для crm.lead.add / crm.contact.add
/// только из того, что видно менеджеру (скрытые ветки не отправляются).
class LeadFormData extends ChangeNotifier {
  final Map<String, String> single = {};       // поле → ID выбранного варианта
  final Map<String, Set<String>> multi = {};   // поле → ID выбранных вариантов
  final Map<String, String> text = {};         // текстовые и числовые поля
  final Set<String> rooms = {};                // выбранные помещения (label)
  bool? sameHeight;                            // null — не выбрано
  bool? separateStyle;                         // null — не выбрано; false — общий; true — раздельный
  String email = '';
  DateTime? birthDate;
  String iin = '';
  String whatSought = '';

  void setSingle(String field, String? id) {
    if (id == null || single[field] == id) {
      single.remove(field); // повторное нажатие снимает выбор
    } else {
      single[field] = id;
    }
    notifyListeners();
  }

  void toggleMulti(String field, String id) {
    final s = multi.putIfAbsent(field, () => <String>{});
    s.contains(id) ? s.remove(id) : s.add(id);
    notifyListeners();
  }

  void setText(String field, String v) {
    v.trim().isEmpty ? text.remove(field) : text[field] = v.trim();
  }

  void toggleRoom(String label) {
    rooms.contains(label) ? rooms.remove(label) : rooms.add(label);
    notifyListeners();
  }

  void setSameHeight(bool v) { sameHeight = sameHeight == v ? null : v; notifyListeners(); }
  void setSeparateStyle(bool v) { separateStyle = separateStyle == v ? null : v; notifyListeners(); }
  void touch() => notifyListeners();

  List<LfRoom> get selectedRooms => lfRooms.where((r) => rooms.contains(r.label)).toList();
  bool get extraLight => single[LfF.extraLight] == lfExtraLightYes;

  /// Обязательные поля, как в форме на сайте. null — всё заполнено.
  String? validate() {
    if (!single.containsKey(LfF.gender)) return 'Укажите пол клиента';
    if (!single.containsKey(LfF.source)) return 'Укажите, откуда пришёл клиент';
    if (!single.containsKey(LfF.age)) return 'Укажите возраст клиента';
    if (!single.containsKey(LfF.psychotype)) return 'Укажите психотип клиента';
    if (iin.trim().isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(iin.trim())) return 'ИИН — 12 цифр';
    if (email.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      return 'Проверьте e-mail';
    }
    return null;
  }

  num? _num(String? s) => s == null ? null : num.tryParse(s.replaceAll(',', '.').trim());

  /// Поля лида.
  Map<String, dynamic> leadFields() {
    final f = <String, dynamic>{};
    void put1(String field) { final v = single[field]; if (v != null) f[field] = v; }
    void putN(String field) { final v = multi[field]; if (v != null && v.isNotEmpty) f[field] = v.toList(); }
    void putNum(String field) { final v = _num(text[field]); if (v != null) f[field] = v; }
    void putText(String field) { final v = text[field]; if (v != null) f[field] = v; }

    put1(LfF.gender);
    final rooms = selectedRooms;
    if (sameHeight != null) {
      f[LfF.sameHeight] = sameHeight! ? '16971' : '16973';
      if (rooms.isNotEmpty) {
        f[sameHeight! ? LfF.roomsSame : LfF.roomsDiff] =
            rooms.map((r) => sameHeight! ? r.sameId : r.diffId).toList();
      }
      if (sameHeight!) {
        put1(LfF.heightAll);
        if (lfIsCustom(LfF.heightAll, single[LfF.heightAll])) putNum(LfF.heightAllCustom);
      } else {
        for (final r in rooms) {
          put1(r.height);
          if (lfIsCustom(r.height, single[r.height])) putNum(r.heightCustom);
        }
      }
    }
    if (rooms.any((r) => r.label == 'Прочее')) putText(LfF.otherText);
    for (final r in rooms) { put1(r.area); }

    put1(LfF.extraLight);
    if (extraLight) {
      for (final r in rooms) {
        put1(r.points);
        if (lfIsCustom(r.points, single[r.points])) putNum(r.pointsCustom);
        put1(r.pointsType);
      }
    }

    if (separateStyle != null) {
      // «Стиль для комнат» в форме — два поля для двух веток высоты потолков
      final same = sameHeight != false;
      f[same ? LfF.styleModeSame : LfF.styleModeDiff] = [
        separateStyle! ? (same ? '17031' : '17229') : (same ? '17029' : '17227'),
      ];
      if (separateStyle!) {
        for (final r in rooms) { put1(r.style); }
      } else {
        put1(LfF.styleAll);
      }
    }

    put1(LfF.source);
    if (single[LfF.source] == lfSourceOther) putText(LfF.sourceText);
    put1(LfF.repairStage);
    put1(LfF.age);
    put1(LfF.psychotype);
    put1(LfF.peopleCount);
    putN(LfF.whoWasWith);
    put1(LfF.category);
    return f;
  }

  /// Поля контакта.
  Map<String, dynamic> contactFields() {
    final f = <String, dynamic>{};
    if (email.trim().isNotEmpty) f['EMAIL'] = [{'VALUE': email.trim(), 'VALUE_TYPE': 'WORK'}];
    if (birthDate != null) {
      final d = birthDate!;
      f['BIRTHDATE'] = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    if (iin.trim().isNotEmpty) f[LfF.iin] = iin.trim();
    final coffee = multi[LfF.coffee];
    if (coffee != null && coffee.isNotEmpty) f[LfF.coffee] = coffee.toList();
    return f;
  }
}
