import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/checkout/order_success_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/cart/models/cart_model.dart';
import 'package:offlinesvet/common/animated_search_bar.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:offlinesvet/checkout/order_data_service.dart';

// -------------------------------------------------------
// Модель купона (список купонов, только визуал)
// -------------------------------------------------------
class CouponGroup {
  final String name;
  final List<String> codes;
  const CouponGroup({required this.name, required this.codes});
  factory CouponGroup.fromJson(Map<String, dynamic> j) => CouponGroup(
    name: j['NAME'] as String,
    codes: List<String>.from(j['LIST'] as List),
  );
}

// -------------------------------------------------------
// Результат применения купонов с сервера
// -------------------------------------------------------
class CouponResult {
  /// product_id → цена за единицу ПОСЛЕ скидки
  final Map<int, double> prices;
  /// product_id → базовая цена до скидки
  final Map<int, double> basePrices;
  /// product_id → процент скидки
  final Map<int, int> discountPercents;
  /// product_id → код купона который сработал (или null)
  final Map<int, String?> appliedCoupons;
  final List<String> couponsApplied;
  final List<String> couponsIgnored;
  final List<String> couponsInvalid;

  const CouponResult({
    required this.prices,
    required this.basePrices,
    required this.discountPercents,
    required this.appliedCoupons,
    required this.couponsApplied,
    required this.couponsIgnored,
    required this.couponsInvalid,
  });

  static CouponResult empty() => const CouponResult(
    prices: {}, basePrices: {}, discountPercents: {},
    appliedCoupons: {}, couponsApplied: [], couponsIgnored: [], couponsInvalid: [],
  );

  factory CouponResult.fromJson(Map<String, dynamic> j) {
    final prices       = <int, double>{};
    final basePrices   = <int, double>{};
    final discPcts     = <int, int>{};
    final appCoupons   = <int, String?>{};

    for (final item in (j['items'] as List? ?? [])) {
      final pid = (item['product_id'] as num).toInt();
      prices[pid]      = (item['price'] as num).toDouble();
      basePrices[pid]  = (item['base_price'] as num).toDouble();
      discPcts[pid]    = (item['discount_percent'] as num).toInt();
      appCoupons[pid]  = item['coupon_applied'] as String?;
    }

    return CouponResult(
      prices:           prices,
      basePrices:       basePrices,
      discountPercents: discPcts,
      appliedCoupons:   appCoupons,
      couponsApplied:   List<String>.from(j['coupons_applied'] ?? []),
      couponsIgnored:   List<String>.from(j['coupons_ignored'] ?? []),
      couponsInvalid:   List<String>.from(j['coupons_invalid'] ?? []),
    );
  }
}

// -------------------------------------------------------
// Аргументы экрана
// -------------------------------------------------------
class CheckoutScreenArgs {
  final Cart cart;
  final Map<String, Product> productsCache;
  const CheckoutScreenArgs({required this.cart, required this.productsCache});
}

// -------------------------------------------------------
// ID свойств Bitrix
// -------------------------------------------------------
const _pNamePhys      = 23;
const _pPhonePhys     = 24;
const _pClientType    = 32;
const _pProject       = 214;
const _pCategory      = 219;
const _pStatus        = 143;
const _pPlace         = 124;
const _pSource        = 61;
const _pArea          = 251;
const _pObjType       = 249;
const _pManager       = 29;
const _pCompany       = 146;
const _pContactName   = 156;
const _pPhoneLegal    = 186;
const _pCompanyFull   = 158; // Полное наименование компании
const _pCompanyEmail  = 187; // Email компании
const _pCompanyBin    = 155; // БИН/ИИН

// Скрытые поля физ. лица (из HL-блока 45)
const _pH1cOrgFiz  = 144; // Организация (физ)
const _pH1cDepFiz  = 145; // Подразделение (физ)
const _pH1cAuthFiz = 150; // Автор (физ)
const _pH1cStoreFiz= 159; // Склад (физ)
const _pH1cShopFiz = 217; // Магазин (физ)
const _pH1cBaseFiz = 151; // База 1С (физ)

// Скрытые поля юр. лица (из HL-блока 45)
const _pH1cOrgYur  = 147; // Организация (юр)
const _pH1cDepYur  = 148; // Подразделение (юр)
const _pH1cAuthYur = 152; // Автор (юр)
const _pH1cStoreYur= 160; // Склад (юр)
const _pH1cShopYur = 218; // Магазин (юр)
const _pH1cBaseYur = 153; // База 1С (юр)

const _pProjectLegal  = 260;
const _pCategoryLegal = 222;
const _pStatusLegal   = 161;
const _pPlaceLegal    = 223;
const _pSourceLegal   = 221;
const _pAreaLegal     = 250;
const _pObjTypeLegal  = 248;
const _pManagerLegal  = 149;
const _kPlacesFallback = ['Онлайн', 'На выезде', 'В отделе'];

// -------------------------------------------------------
// Экран
// -------------------------------------------------------
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';
  final _dio = Dio();
  final _orderDataService = OrderDataService();

  late Cart _cart;
  late Map<String, Product> _productsCache;

  OrderData? _od;
  bool _dataLoading = true;
  String? _dataError;

  bool _isLegal     = false;
  int  _deliveryId  = 25;
  final Set<int> _selectedExtras = {};

  final _extraServiceCtrl = TextEditingController();
  final _nameCtrl          = TextEditingController(); // ФИО контакта (физ) / ФИО контактного лица (юр)
  final _phoneCtrl         = TextEditingController(); // Телефон контакта (физ) / Телефон компании (юр)
  final _projectCtrl       = TextEditingController();
  final _areaCtrl          = TextEditingController();
  final _companyCtrl       = TextEditingController(); // Наименование компании (юр)
  final _companyFullCtrl   = TextEditingController(); // Полное наименование компании (юр)
  final _companyEmailCtrl  = TextEditingController(); // Email компании (юр)
  final _companyBinCtrl    = TextEditingController(); // БИН/ИИН (юр)
  final _couponCtrl        = TextEditingController();

  String? _clientType   = 'Клиент';
  String  _orderStatus  = 'order-status-kp';
  String  _servicePlace = 'В отделе';
  String? _clientSource;
  String? _objectType;
  String? _manager;
  final List<String> _categories = [];

  bool _loading     = false;
  bool _initialized = false;
  String? _error;

  // Список купонов-INVEST загружается с сервера (coupon_rules.php → invest_coupons)
  List<String> _investCoupons = [];

  // Данные из HL-блока 45 (скрытые поля)
  ManagerProps _managerProps = ManagerProps.empty();

  // Контроллеры скрытых полей
  final _h1cOrgCtrl   = TextEditingController();
  final _h1cDepCtrl   = TextEditingController();
  final _h1cAuthCtrl  = TextEditingController();
  final _h1cStoreCtrl = TextEditingController();
  final _h1cShopCtrl  = TextEditingController();
  String _h1cBase1c   = ''; // base-1c-aura / base-1c-invest

  // ── Купоны ──────────────────────────────────────────
  List<CouponGroup> _couponGroups = [];
  bool _couponsLoading = false;
  final List<String> _selectedCoupons = [];

  /// Результат с сервера после применения купонов
  CouponResult _couponResult = CouponResult.empty();
  bool _couponApplying = false; // идёт запрос к серверу

  // -------------------------------------------------------
  // Геттеры OrderData
  // -------------------------------------------------------
  List<DeliveryService> get _deliveries => _od?.deliveries ?? const [];
  List<DeliveryExtraService> get _currentExtras =>
      _od?.extrasForDelivery(_deliveryId) ?? const [];
  List<String> _names(int propId) => _od?.variantNames(propId) ?? const [];
  List<String> get _clientTypes =>
      _names(_pClientType).isNotEmpty ? _names(_pClientType) : ['Дизайнер', 'Клиент'];
  List<Map<String, String>> get _statuses {
    final v = _od?.variants(_pStatus) ?? const [];
    if (v.isEmpty) return [
      {'value': 'order-status-kp',   'label': 'КП'},
      {'value': 'order-status-sale', 'label': 'Заказ в 1С'},
    ];
    return v.map((e) => {'value': e.value, 'label': e.name}).toList();
  }
  List<String> get _places {
    final v = _names(_isLegal ? _pPlaceLegal : _pPlace);
    return v.isNotEmpty ? v : _kPlacesFallback;
  }
  List<String> get _sources => _names(_isLegal ? _pSourceLegal : _pSource);
  List<String> get _catList => _names(_isLegal ? _pCategoryLegal : _pCategory);
  List<String> get _objTypes => _names(_isLegal ? _pObjTypeLegal : _pObjType);
  List<String> get _managers => _names(_isLegal ? _pManagerLegal : _pManager);

  // -------------------------------------------------------
  // Инициализация
  // -------------------------------------------------------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments as CheckoutScreenArgs?;
    if (args != null) {
      _cart = args.cart;
      _productsCache = args.productsCache;
      final client = _cart.clientInfo;
      if (client != null) {
        final entity = client['ENTITY']?.toString() ?? '';

        if (entity == 'COMPANY') {
          // Компания — автоматически юр. лицо
          _isLegal = true;

          // Наименование компании (краткое) — TITLE в clientInfo
          final title = client['TITLE']?.toString() ?? '';
          if (title.isNotEmpty) _companyCtrl.text = title;

          // БИН/ИИН — BIN в clientInfo
          final bin = client['BIN']?.toString() ?? '';
          if (bin.isNotEmpty) _companyBinCtrl.text = bin;
        } else {
          // Контакт — физ. лицо
          final name  = client['NAME']?.toString()  ?? '';
          final phone = client['PHONE']?.toString() ?? '';
          if (name.isNotEmpty)  _nameCtrl.text  = name;
          if (phone.isNotEmpty) _phoneCtrl.text = _formatPhone(phone);
        }
      }
    }
    _loadOrderData();
    _loadCouponGroups();
    // Дозаполняем поля из Customer (fullName, phone, email) — читаем из хранилища
    _prefillFromCustomer();
  }

  Future<void> _loadOrderData() async {
    try {
      final data = await _orderDataService.load();
      if (!mounted) return;
      setState(() {
        _od = data;
        _dataLoading = false;
        if (data.deliveries.isNotEmpty) _deliveryId = data.deliveries.first.id;
      });
      // Загружаем скрытые поля из HL-45 по manager_id
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId != null) {
        final props = await _orderDataService.loadManagerProps(managerId);
        if (!mounted) return;
        setState(() { _managerProps = props; });
        _applyManagerProps(); // применяем сразу
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _dataError = e.toString(); _dataLoading = false; });
    }
  }

  /// Применяет скрытые поля из HL-45 в зависимости от типа (юр/физ/invest)
  void _applyManagerProps() {
    final isInvest = _investCoupons.isNotEmpty && _selectedCoupons.any((c) => _investCoupons.contains(c));

    // Определяем режим и ключи в зависимости от него
    final Map<String, String> map;
    final int orgKey, depKey, authKey, storeKey, shopKey, baseKey;

    if (_isLegal) {
      map = _managerProps.yur;
      orgKey = _pH1cOrgYur; depKey = _pH1cDepYur; authKey = _pH1cAuthYur;
      storeKey = _pH1cStoreYur; shopKey = _pH1cShopYur; baseKey = _pH1cBaseYur;
    } else if (isInvest) {
      // Физ. лицо с купоном ≥25% — данные как у юр. лица, но поля физ. лица
      map = _managerProps.invest;
      orgKey = _pH1cOrgFiz; depKey = _pH1cDepFiz; authKey = _pH1cAuthFiz;
      storeKey = _pH1cStoreFiz; shopKey = _pH1cShopFiz; baseKey = _pH1cBaseFiz;
    } else {
      map = _managerProps.fiz;
      orgKey = _pH1cOrgFiz; depKey = _pH1cDepFiz; authKey = _pH1cAuthFiz;
      storeKey = _pH1cStoreFiz; shopKey = _pH1cShopFiz; baseKey = _pH1cBaseFiz;
    }

    if (map.isEmpty) return;

    setState(() {
      _h1cOrgCtrl.text   = map[orgKey.toString()]   ?? '';
      _h1cDepCtrl.text   = map[depKey.toString()]   ?? '';
      _h1cAuthCtrl.text  = map[authKey.toString()]  ?? '';
      _h1cStoreCtrl.text = map[storeKey.toString()] ?? '';
      _h1cShopCtrl.text  = map[shopKey.toString()]  ?? '';
      _h1cBase1c         = map[baseKey.toString()]  ?? '';
    });
  }

  /// Загружает список групп купонов с сервера (coupon_rules.php)
  /// Дозаполняет поля из Customer.loadActive() — fullName, phone, email.
  /// Вызывается после didChangeDependencies, когда clientInfo уже обработан.
  Future<void> _prefillFromCustomer() async {
    final customer = await CustomerStorage.loadActive();
    if (customer == null || !mounted) return;

    if (customer.isCompany) {
      setState(() {
        // Полное наименование (хранится в lastName — см. search_customer_screen)
        if (customer.lastName.isNotEmpty) _companyFullCtrl.text = customer.lastName;
        // Телефон компании
        if (customer.phone.isNotEmpty) _phoneCtrl.text = _formatPhone(customer.phone);
        // Email компании
        if (customer.email.isNotEmpty) _companyEmailCtrl.text = customer.email;
      });
    }
  }

  Future<void> _loadCouponGroups() async {
    setState(() => _couponsLoading = true);
    try {
      final resp = await _dio.get(
        '$_baseUrl/coupon_rules.php',
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(resp.data as String) as Map<String, dynamic>;
      final groups = (json['groups'] as List? ?? [])
          .map((e) => CouponGroup.fromJson(e as Map<String, dynamic>))
          .toList();
      final investList = (json['invest_coupons'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (!mounted) return;
      setState(() {
        _couponGroups = groups;
        if (investList.isNotEmpty) _investCoupons = investList;
        _couponsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _couponsLoading = false);
    }
  }

  /// Отправляет выбранные купоны на сервер и получает пересчитанные цены
  Future<void> _applyCouponsOnServer() async {
    if (_selectedCoupons.isEmpty) {
      setState(() => _couponResult = CouponResult.empty());
      return;
    }
    setState(() => _couponApplying = true);
    try {
      final resp = await _dio.post(
        '$_baseUrl/apply_coupons.php',
        data: jsonEncode({
          'basket_id': int.parse(_cart.id),
          'coupons'  : _selectedCoupons,
        }),
        options: Options(contentType: 'application/json', responseType: ResponseType.plain),
      );
      final json = jsonDecode(resp.data as String) as Map<String, dynamic>;
      if (json['success'] == true) {
        if (!mounted) return;
        setState(() { _couponResult = CouponResult.fromJson(json); });
      }
    } catch (e) {
      debugPrint('apply_coupons error: $e');
    } finally {
      if (mounted) setState(() => _couponApplying = false);
    }
  }

  String _formatPhone(String raw) {
    final d = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (d.length == 11) return '+7 (${d.substring(1,4)}) ${d.substring(4,7)} ${d.substring(7,9)} ${d.substring(9,11)}';
    if (d.length == 10) return '+7 (${d.substring(0,3)}) ${d.substring(3,6)} ${d.substring(6,8)} ${d.substring(8,10)}';
    return raw;
  }

  @override
  void dispose() {
    for (final c in [_extraServiceCtrl, _nameCtrl, _phoneCtrl,
                     _projectCtrl, _areaCtrl, _companyCtrl,
                     _companyFullCtrl, _companyEmailCtrl, _companyBinCtrl,
                     _h1cOrgCtrl, _h1cDepCtrl, _h1cAuthCtrl,
                     _h1cStoreCtrl, _h1cShopCtrl,
                     _couponCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------
  // Цены — берём из результата сервера, фолбэк — локальный расчёт
  // -------------------------------------------------------

  /// Базовая цена из кэша (без купонов)
  double _rawPrice(CartItem item) {
    final p = _productsCache[item.productId.toString()];
    if (p == null || p.prices.isEmpty) return 0;
    return p.prices.map((x) => x.price).reduce((a, b) => a < b ? a : b);
  }

  /// Локальный расчёт скидки по купону для одного товара.
  /// Логика "max скидка побеждает" — берём максимальный процент
  /// из всех подходящих купонов (не суммируем, как в Bitrix).
  int _localDiscountPercent(CartItem item) {
    if (_selectedCoupons.isEmpty) return 0;
    final productName = (_productsCache[item.productId.toString()]?.name ?? '').toLowerCase();
    int maxDiscount = 0;

    for (final code in _selectedCoupons) {
      final upper = code.toUpperCase();
      // Извлекаем процент из кода: SVET10% → 10, CT40% → 40
      final pct = _extractPercent(code);
      if (pct == 0) continue;

      bool applies = false;

      if (upper.startsWith('CT')) {
        // Распродажа ВИТРИНА — только к товарам с rasprodazha != "Без скидки"
        // И процент купона должен совпадать с процентом в rasprodazha
        final raspPct = _extractPercent(item.rasprodazha);
        applies = item.rasprodazha.isNotEmpty &&
            item.rasprodazha != 'Без скидки' &&
            raspPct == pct;
      } else if (upper.startsWith('MAYTONI-FREYA')) {
        applies = productName.contains('maytoni') || productName.contains('freya');
      } else if (upper.startsWith('SVET-R')) {
        applies = productName.contains('voltum') ||
            productName.contains('розетк') ||
            productName.contains('выключател');
      } else if (upper.startsWith('SVET-L')) {
        applies = productName.contains('лампоч') ||
            productName.contains('lamp') ||
            productName.contains('светодиод');
      } else {
        // SVET%, SVET-PR%, SVET-BOSS%, SVET-V% — ко всем товарам
        applies = true;
      }

      if (applies && pct > maxDiscount) maxDiscount = pct;
    }
    return maxDiscount;
  }

  /// Извлекает число из строки вида "SVET10%" → 10, "Распродажа 20%" → 20
  int _extractPercent(String s) {
    final match = RegExp(r'(\d+)%').firstMatch(s);
    return match != null ? int.tryParse(match.group(1) ?? '') ?? 0 : 0;
  }

  double _unitPrice(CartItem item) {
    // Приоритет 1: результат с сервера
    final serverPrice = _couponResult.prices[item.productId];
    if (serverPrice != null) return serverPrice;
    // Приоритет 2: локальный расчёт
    final base = _rawPrice(item);
    final pct = _localDiscountPercent(item);
    if (pct > 0) return base * (1 - pct / 100);
    return base;
  }

  double _baseUnitPrice(CartItem item) {
    final serverBase = _couponResult.basePrices[item.productId];
    if (serverBase != null) return serverBase;
    return _rawPrice(item);
  }

  int _discountPercent(CartItem item) {
    final serverPct = _couponResult.discountPercents[item.productId];
    if (serverPct != null && serverPct > 0) return serverPct;
    return _localDiscountPercent(item);
  }

  double get _totalProducts =>
      _cart.items.fold(0.0, (s, i) => s + _unitPrice(i) * i.quantity);

  double get _deliveryCost {
    if (_deliveryId == 32) return 10000;
    if (_deliveryId == 17) return double.tryParse(_extraServiceCtrl.text.trim()) ?? 0;
    return _currentExtras
        .where((e) => _selectedExtras.contains(e.id))
        .fold(0.0, (s, e) => s + e.price);
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₸';
  }

  // -------------------------------------------------------
  // Логика визуальной применимости купона (до ответа сервера)
  // Используется только для подсветки в UI
  // -------------------------------------------------------
  bool _couponLikelyApplies(String code) {
    final upper = code.toUpperCase();

    if (upper.startsWith('CT')) {
      // CT40% применяется только к товарам у которых rasprodazha == "Распродажа 40%"
      final pct = _extractPercent(code);
      return _cart.items.any((i) {
        final raspPct = _extractPercent(i.rasprodazha);
        return i.rasprodazha.isNotEmpty &&
            i.rasprodazha != 'Без скидки' &&
            raspPct == pct;
      });
    }

    // MAYTONI-FREYA — к товарам с этим названием
    if (upper.startsWith('MAYTONI-FREYA')) {
      return _cart.items.any((i) {
        final name = (_productsCache[i.productId.toString()]?.name ?? '').toLowerCase();
        return name.contains('maytoni') || name.contains('freya');
      });
    }

    // SVET-R — розетки (Voltum в названии)
    if (upper.startsWith('SVET-R')) {
      return _cart.items.any((i) {
        final name = (_productsCache[i.productId.toString()]?.name ?? '').toLowerCase();
        return name.contains('voltum') || name.contains('розетк');
      });
    }

    // SVET-L — лампочки
    if (upper.startsWith('SVET-L')) {
      return _cart.items.any((i) {
        final name = (_productsCache[i.productId.toString()]?.name ?? '').toLowerCase();
        return name.contains('лампоч') || name.contains('lamp');
      });
    }

    // Остальные (SVET%, SVET-PR%, BOSS%, V%) — ко всем товарам
    return _cart.items.isNotEmpty;
  }

  // Купон реально применился на сервере?
  bool _couponAppliedOnServer(String code) =>
      _couponResult.couponsApplied.contains(code);

  // -------------------------------------------------------
  // Отправка заказа
  // -------------------------------------------------------
  Future<void> _submit() async {
    // Валидация: для юр. лица обязательно только наименование компании
    if (_isLegal) {
      if (_companyCtrl.text.trim().isEmpty) { setState(() => _error = 'Укажите наименование компании'); return; }
    } else {
      if (_nameCtrl.text.trim().isEmpty) { setState(() => _error = 'Укажите имя клиента'); return; }
      if (_phoneCtrl.text.trim().isEmpty) { setState(() => _error = 'Укажите телефон'); return; }
      if (_clientType == null) { setState(() => _error = 'Выберите тип клиента'); return; }
    }

    setState(() { _loading = true; _error = null; });

    try {
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) throw Exception('Не удалось определить менеджера');

      final props = _isLegal ? {
        '$_pCompany'      : _companyCtrl.text.trim(),
        '$_pCompanyFull'  : _companyFullCtrl.text.trim(),
        '$_pCompanyEmail' : _companyEmailCtrl.text.trim(),
        '$_pCompanyBin'   : _companyBinCtrl.text.trim(),
        '$_pContactName'  : _nameCtrl.text.trim(),
        '$_pPhoneLegal'   : _phoneCtrl.text.trim(),
        // Скрытые поля юр. лица из HL-45
        '$_pH1cOrgYur'   : _h1cOrgCtrl.text.trim(),
        '$_pH1cDepYur'   : _h1cDepCtrl.text.trim(),
        '$_pH1cAuthYur'  : _h1cAuthCtrl.text.trim(),
        '$_pH1cStoreYur' : _h1cStoreCtrl.text.trim(),
        '$_pH1cShopYur'  : _h1cShopCtrl.text.trim(),
        '$_pH1cBaseYur'  : _h1cBase1c,
        '$_pProjectLegal' : _projectCtrl.text.trim(),
        '$_pCategoryLegal': _categories,
        '$_pStatusLegal'  : _orderStatus,
        '$_pPlaceLegal'   : _servicePlace,
        '$_pSourceLegal'  : _clientSource,
        '$_pAreaLegal'    : _areaCtrl.text.trim(),
        '$_pObjTypeLegal' : _objectType,
        '$_pManagerLegal' : _manager,
      } : {
        '$_pNamePhys'  : _nameCtrl.text.trim(),
        '$_pPhonePhys' : _phoneCtrl.text.trim(),
        // Скрытые поля физ. лица из HL-45
        '$_pH1cOrgFiz'   : _h1cOrgCtrl.text.trim(),
        '$_pH1cDepFiz'   : _h1cDepCtrl.text.trim(),
        '$_pH1cAuthFiz'  : _h1cAuthCtrl.text.trim(),
        '$_pH1cStoreFiz' : _h1cStoreCtrl.text.trim(),
        '$_pH1cShopFiz'  : _h1cShopCtrl.text.trim(),
        '$_pH1cBaseFiz'  : _h1cBase1c,
        '$_pClientType': _clientType,
        '$_pProject'   : _projectCtrl.text.trim(),
        '$_pCategory'  : _categories,
        '$_pStatus'    : _orderStatus,
        '$_pPlace'     : _servicePlace,
        '$_pSource'    : _clientSource,
        '$_pArea'      : _areaCtrl.text.trim(),
        '$_pObjType'   : _objectType,
        '$_pManager'   : _manager,
      };
      props.removeWhere((_, v) => v == null || v == '' || (v is List && (v as List).isEmpty));

      final response = await _dio.post(
        '$_baseUrl/create_order.php',
        data: jsonEncode({
          'manager_id'   : managerId,
          'basket_id'    : int.parse(_cart.id),
          'person_type'  : _isLegal ? 'legal' : 'physical',
          'delivery_id'  : _deliveryId,
          'delivery_cost': _deliveryCost,
          'coupons'      : _selectedCoupons,
          'props'        : props,
        }),
        options: Options(contentType: 'application/json', responseType: ResponseType.plain),
      );

      final result = jsonDecode(response.data as String) as Map<String, dynamic>;
      if (result['success'] == true) {
        final orderId = result['order_id'];
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => OrderSuccessScreen(
            orderId: int.parse(orderId.toString()),
            clientName: _cart.clientInfo?['NAME']?.toString() ?? _cart.title,
          )),
          (_) => false,
        );
      } else {
        setState(() => _error = result['error'] ?? 'Неизвестная ошибка');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------------
  // Build
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_dataLoading) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const AppBottomNavBar(currentTab: null),
      );
    }
    if (_dataError != null) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_dataError!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () { setState(() { _dataLoading = true; _dataError = null; }); _loadOrderData(); },
            child: const Text('Повторить'),
          ),
        ])),
        bottomNavigationBar: const AppBottomNavBar(currentTab: null),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildCouponBlock(),
          _CollapsibleSection(number: 1, title: 'Товары в заказе', child: _buildProductList()),
          _CollapsibleSection(number: 2, title: 'Тип плательщика', child: _buildToggle(
            options: ['Физическое лицо', 'Юридическое лицо'],
            selected: _isLegal ? 1 : 0,
            onChanged: (i) {
              setState(() => _isLegal = i == 1);
              _applyManagerProps();
            },
          )),
          _CollapsibleSection(number: 3, title: 'Доставка', child: _buildDeliveryBlock()),
          _CollapsibleSection(number: 4, title: 'Оплата', child: _buildPaymentBlock()),
          _CollapsibleSection(number: 5, title: 'Покупатель', child: _buildBuyerForm()),
          _buildTotalBlock(),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
          ),
        GestureDetector(
          onTap: _loading ? null : _submit,
          child: Container(
            color: const Color(0xFF4CAF50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Text(_fmt(_totalProducts + _deliveryCost),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              _loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Оформить заказ',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        AppBottomNavBar(currentTab: null, onCartTap: () => Navigator.of(context).pop()),
      ]),
    );
  }

  // ── AppBar — как в каталоге ───────────────────────────
  AppBar _buildAppBar() => AppBar(
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pop(),
    ),
    title: const Text('Оформление заказа'),
    centerTitle: false,
    actions: const [CatalogSearchBar(), SizedBox(width: 8)],
  );

  // ── Купоны ────────────────────────────────────────────
  Widget _buildCouponBlock() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Кнопка "Купоны" на всю ширину
        InkWell(
          onTap: _openCouponSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
            child: Row(children: [
              const Icon(Icons.local_offer_outlined, size: 20, color: Color(0xFF4CAF50)),
              const SizedBox(width: 10),
              const Text('Купоны', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_couponsLoading || _couponApplying)
                const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4CAF50)))
              else
                Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
            ]),
          ),
        ),

        // Поле ручного ввода
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _couponCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Применить купон',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true, fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: _applyManualCoupon,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _applyManualCoupon(),
          ),
        ),

        // Список применённых купонов
        if (_selectedCoupons.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(spacing: 6, runSpacing: 6,
              children: _selectedCoupons.map((code) {
                // Если сервер уже ответил — берём результат оттуда,
                // иначе визуальная предикция по названию купона
                final hasServerResult = _couponResult.couponsApplied.isNotEmpty ||
                    _couponResult.couponsIgnored.isNotEmpty;
                final isActive = hasServerResult
                    ? _couponAppliedOnServer(code)
                    : _couponLikelyApplies(code);

                return _CouponChip(
                  code: code,
                  isActive: isActive,
                  onRemove: () {
                    setState(() => _selectedCoupons.remove(code));
                    _applyCouponsOnServer();
                    _applyManagerProps();
                  },
                );
              }).toList(),
            ),
          ),
        ] else
          const SizedBox(height: 12),
      ]),
    );
  }

  void _applyManualCoupon() {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    if (_selectedCoupons.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Купон уже добавлен'), duration: Duration(seconds: 2)));
      return;
    }
    setState(() {
      _selectedCoupons.add(code);
      _couponCtrl.clear();
    });
    _applyCouponsOnServer();
    _applyManagerProps(); // пересчитываем invest-режим
  }

  void _openCouponSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CouponSheet(
        groups: _couponGroups,
        selectedCoupons: List.from(_selectedCoupons),
        couponLikelyApplies: _couponLikelyApplies,
        onToggle: (code) {
          setState(() {
            if (_selectedCoupons.contains(code)) {
              _selectedCoupons.remove(code);
            } else {
              _selectedCoupons.add(code);
            }
          });
          _applyCouponsOnServer();
          _applyManagerProps(); // пересчитываем invest-режим при выборе в bottom sheet
        },
      ),
    );
  }

  // ── Товары ────────────────────────────────────────────
  Widget _buildProductList() {
    return Column(children: _cart.items.map((item) {
      final product     = _productsCache[item.productId.toString()];
      final unitPrice   = _unitPrice(item);
      final basePrice   = _baseUnitPrice(item);
      final discPct     = _discountPercent(item);
      final hasDiscount = discPct > 0 && basePrice > unitPrice;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Фото
          SizedBox(width: 72, height: 72,
            child: ClipRRect(borderRadius: BorderRadius.circular(8),
              child: product?.image != null
                  ? CachedNetworkImage(imageUrl: product!.image!, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey.shade100),
                      errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: Colors.grey))
                  : Container(color: Colors.grey.shade100,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey)))),
          const SizedBox(width: 12),

          // Название + метки
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product?.name ?? 'Товар #${item.productId}',
              style: const TextStyle(fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            // Выбор помещения
            if (item.selectRoom.isNotEmpty)
              Text(item.selectRoom,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            // Распродажа
            if (item.rasprodazha.isNotEmpty && item.rasprodazha != 'Без скидки') ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(item.rasprodazha,
                  style: const TextStyle(fontSize: 10, color: Color(0xFFE65100), fontWeight: FontWeight.w500)),
              ),
            ],
          ])),
          const SizedBox(width: 8),

          // Цены
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (_couponApplying)
              const SizedBox(width: 40, height: 14,
                child: LinearProgressIndicator(color: Color(0xFF4CAF50), backgroundColor: Color(0xFFE8F5E9)))
            else
              Text(_fmt(unitPrice * item.quantity),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            // Зачёркнутая цена и процент скидки
            if (hasDiscount && !_couponApplying) ...[
              Text(_fmt(basePrice * item.quantity),
                style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade400,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.grey.shade400,
                )),
              Text('-$discPct%',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
            ],
            Text('${item.quantity} шт', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
        ]),
      );
    }).toList());
  }

  // ── Toggle ────────────────────────────────────────────
  Widget _buildToggle({required List<String> options, required int selected, required ValueChanged<int> onChanged}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
      child: Row(children: List.generate(options.length, (i) {
        final isSelected = i == selected;
        return Expanded(child: GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent,
              borderRadius: BorderRadius.horizontal(
                left:  i == 0 ? const Radius.circular(12) : Radius.zero,
                right: i == options.length - 1 ? const Radius.circular(12) : Radius.zero,
              ),
            ),
            child: Text(options[i], textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14,
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
          ),
        ));
      })),
    );
  }

  // ── Доставка ──────────────────────────────────────────
  Widget _buildDeliveryBlock() {
    final deliveries = _deliveries;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: deliveries.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 3.2, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemBuilder: (_, i) {
          final d = deliveries[i]; final isSelected = d.id == _deliveryId;
          return GestureDetector(
            onTap: () => setState(() { _deliveryId = d.id; _selectedExtras.clear(); }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150), alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
              child: Text(d.name, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      _buildDeliveryDetails(),
    ]);
  }

  Widget _buildDeliveryDetails() {
    final extras = _currentExtras;
    final sel = _deliveries.where((d) => d.id == _deliveryId).firstOrNull;
    if (sel == null) return const SizedBox.shrink();
    if (_deliveryId == 32) return _buildInfoBlock(title: sel.name, description: sel.description, cost: 10000, costColor: Colors.red);
    if (_deliveryId == 33) return _buildInfoBlock(title: sel.name,
      description: sel.description.isNotEmpty ? sel.description : 'Срок доставки: от 5 до 18 дней', cost: 0);
    if (_deliveryId == 17) {
      return Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sel.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (sel.description.isNotEmpty) ...[const SizedBox(height: 4), Text(sel.description, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))],
          const SizedBox(height: 10),
          TextField(controller: _extraServiceCtrl, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'Сумма за установку (₸)', hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
          const SizedBox(height: 8), _costRow(_deliveryCost),
        ]));
    }
    if (extras.isEmpty) return const SizedBox.shrink();
    final left  = extras.length > 4 ? extras.sublist(0, 4) : extras;
    final right = extras.length > 4 ? extras.sublist(4) : <DeliveryExtraService>[];
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(sel.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text('Стоимость  ${_fmt(_deliveryCost)}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: left.map((e) => _ZoneCheckbox(label: e.name, price: _fmt(e.price), selected: _selectedExtras.contains(e.id),
            onTap: () => setState(() { _selectedExtras.contains(e.id) ? _selectedExtras.remove(e.id) : _selectedExtras.add(e.id); }))).toList())),
          if (right.isNotEmpty) ...[const SizedBox(width: 12),
            Expanded(child: Column(children: right.map((e) => _ZoneCheckbox(label: e.name, price: _fmt(e.price), selected: _selectedExtras.contains(e.id),
              onTap: () => setState(() { _selectedExtras.contains(e.id) ? _selectedExtras.remove(e.id) : _selectedExtras.add(e.id); }))).toList()))],
        ]),
      ]));
  }

  Widget _buildInfoBlock({required String title, required String description, required double cost, Color? costColor}) {
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        if (description.isNotEmpty) ...[const SizedBox(height: 6), Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))],
        const SizedBox(height: 8), _costRow(cost, color: costColor),
      ]));
  }

  Widget _costRow(double cost, {Color? color}) => Row(children: [
    Text('Стоимость:', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
    const SizedBox(width: 8),
    Text(_fmt(cost), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? Colors.black87)),
  ]);

  Widget _buildPaymentBlock() => FilledButton(onPressed: null,
    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      disabledBackgroundColor: const Color(0xFF4CAF50), disabledForegroundColor: Colors.white),
    child: const Text('Оплата QR кодом Каспи', style: TextStyle(fontSize: 15)));

  Widget _buildBuyerForm() {
    final statusIdx = _statuses.indexWhere((s) => s['value'] == _orderStatus);
    final placeIdx  = _places.indexOf(_servicePlace);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!_isLegal) ...[
        _FieldLabel(label: 'Тип клиента', required: true), const SizedBox(height: 6),
        _buildToggle(options: _clientTypes, selected: _clientTypes.indexOf(_clientType ?? '').clamp(0, _clientTypes.length - 1),
          onChanged: (i) => setState(() => _clientType = _clientTypes[i])), const SizedBox(height: 16),
      ],
      _FieldLabel(label: 'Название проекта/объекта', required: true), const SizedBox(height: 6),
      _buildTextField(_projectCtrl), const SizedBox(height: 16),
      _FieldLabel(label: 'Категории товаров', required: true), const SizedBox(height: 6),
      _buildCheckboxGrid(items: _catList, selected: _categories,
        onToggle: (v) => setState(() => _categories.contains(v) ? _categories.remove(v) : _categories.add(v))),
      const SizedBox(height: 16),
      _FieldLabel(label: 'Состояние заказа', required: true),
      Text('Присвоение статуса заказа после его оформления', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      const SizedBox(height: 6),
      _buildToggle(options: _statuses.map((s) => s['label']!).toList(), selected: statusIdx < 0 ? 0 : statusIdx,
        onChanged: (i) => setState(() => _orderStatus = _statuses[i]['value']!)), const SizedBox(height: 16),
      _FieldLabel(label: 'Место обслуживания клиента', required: true), const SizedBox(height: 6),
      _buildToggle(options: _places, selected: placeIdx < 0 ? 0 : placeIdx,
        onChanged: (i) => setState(() => _servicePlace = _places[i])), const SizedBox(height: 16),
      _FieldLabel(label: _isLegal ? 'Источник клиента для салонов 2025' : 'Источник клиента для салонов 2026',
        hint: 'Откуда клиент узнал о компании', required: true), const SizedBox(height: 6),
      _buildSelectGrid(items: _sources, selected: _clientSource, onSelect: (v) => setState(() => _clientSource = v)),
      const SizedBox(height: 16),
      // ФИО контактного лица (для юр. лица) или Имя клиента (для физ.)
      if (_isLegal) ...[        _FieldLabel(label: 'ФИО контактного лица'), const SizedBox(height: 6),
        _buildTextField(_nameCtrl), const SizedBox(height: 16),
      ] else ...[        _FieldLabel(label: 'Имя клиента', required: true), const SizedBox(height: 6),
        _buildTextField(_nameCtrl), const SizedBox(height: 16),
        _FieldLabel(label: 'Телефон клиента', required: true), const SizedBox(height: 6),
        _PhoneField(controller: _phoneCtrl),
      ],
      _FieldLabel(label: 'Площадь объекта (квадратура)', required: true), const SizedBox(height: 6),
      _buildTextField(_areaCtrl, keyboardType: TextInputType.number), const SizedBox(height: 16),
      _FieldLabel(label: 'Тип объекта', required: true), const SizedBox(height: 6),
      _buildCheckboxGrid(items: _objTypes, selected: _objectType != null ? [_objectType!] : [], singleSelect: true,
        onToggle: (v) => setState(() => _objectType = _objectType == v ? null : v)), const SizedBox(height: 16),
      // ── Поля юр. лица (только при _isLegal) ──────────────────────
      if (_isLegal) ...[        _FieldLabel(label: 'Наименование компании', required: true), const SizedBox(height: 6),
        _buildTextField(_companyCtrl), const SizedBox(height: 16),
        _FieldLabel(label: 'Полное наименование компании'), const SizedBox(height: 6),
        _buildTextField(_companyFullCtrl), const SizedBox(height: 16),
        _FieldLabel(label: 'Email'), const SizedBox(height: 6),
        _buildTextField(_companyEmailCtrl, keyboardType: TextInputType.emailAddress), const SizedBox(height: 16),
        _FieldLabel(label: 'Телефон компании'), const SizedBox(height: 6),
        _PhoneField(controller: _phoneCtrl),
        _FieldLabel(label: 'БИН/ИИН'), const SizedBox(height: 6),
        _buildTextField(_companyBinCtrl, keyboardType: TextInputType.number), const SizedBox(height: 16),
      ],
      _FieldLabel(label: 'Менеджер клиента', required: true), const SizedBox(height: 6),
      _buildSelectGrid(items: _managers, selected: _manager, onSelect: (v) => setState(() => _manager = v)),

      // ── Скрытые поля из HL-блока 45 (временно видимые для проверки) ─
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9C4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF9A825)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Скрытые поля 1С (временно видимые)',
            style: TextStyle(fontSize: 12, color: Color(0xFFE65100), fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _FieldLabel(label: 'Организация'),
          const SizedBox(height: 4),
          _buildTextField(_h1cOrgCtrl), const SizedBox(height: 12),
          _FieldLabel(label: 'Подразделение'),
          const SizedBox(height: 4),
          _buildTextField(_h1cDepCtrl), const SizedBox(height: 12),
          _FieldLabel(label: 'Автор'),
          const SizedBox(height: 4),
          _buildTextField(_h1cAuthCtrl), const SizedBox(height: 12),
          _FieldLabel(label: 'Склад'),
          const SizedBox(height: 4),
          _buildTextField(_h1cStoreCtrl), const SizedBox(height: 12),
          _FieldLabel(label: 'Магазин'),
          const SizedBox(height: 4),
          _buildTextField(_h1cShopCtrl), const SizedBox(height: 12),
          _FieldLabel(label: 'База 1С'),
          const SizedBox(height: 4),
          _buildToggle(
            options: const ['AURA', 'INVEST'],
            selected: _h1cBase1c == 'base-1c-invest' ? 1 : 0,
            onChanged: (i) => setState(() => _h1cBase1c = i == 1 ? 'base-1c-invest' : 'base-1c-aura'),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildTotalBlock() {
    final delivery = _deliveryCost; final total = _totalProducts + delivery;
    return Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Товаров на', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          Text(_fmt(_totalProducts), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ])),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Доставка', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          Text(delivery == 0 ? 'бесплатно' : _fmt(delivery), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Итого', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          Text(_fmt(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, {String? hint, TextInputType keyboardType = TextInputType.text}) {
    return Padding(padding: const EdgeInsets.only(bottom: 0),
      child: TextField(controller: ctrl, keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: const Color(0xFFF5F5F5), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))));
  }

  Widget _buildCheckboxGrid({required List<String> items, required List<String> selected,
      required ValueChanged<String> onToggle, bool singleSelect = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: singleSelect ? 1 : 2, childAspectRatio: singleSelect ? 7.0 : 4.0),
      itemBuilder: (_, i) {
        final item = items[i]; final isSelected = selected.contains(item);
        return GestureDetector(onTap: () => onToggle(item), child: Row(children: [
          Container(width: 20, height: 20,
            decoration: BoxDecoration(color: isSelected ? const Color(0xFF4CAF50) : Colors.white,
              border: Border.all(color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
            child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
          const SizedBox(width: 8),
          Expanded(child: Text(item, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 2)),
        ]));
      });
  }

  Widget _buildSelectGrid({required List<String> items, required String? selected, required ValueChanged<String> onSelect}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 3.5, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemBuilder: (_, i) {
        final item = items[i]; final isSelected = item == selected;
        return GestureDetector(onTap: () => onSelect(item),
          child: AnimatedContainer(duration: const Duration(milliseconds: 120), alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
            child: Text(item, style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis, maxLines: 2)));
      });
  }
}

// -------------------------------------------------------
// Bottom sheet выбора купонов
// -------------------------------------------------------
class _CouponSheet extends StatefulWidget {
  const _CouponSheet({
    required this.groups, required this.selectedCoupons,
    required this.couponLikelyApplies, required this.onToggle,
  });
  final List<CouponGroup> groups;
  final List<String> selectedCoupons;
  final bool Function(String) couponLikelyApplies;
  final ValueChanged<String> onToggle;
  @override State<_CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends State<_CouponSheet> {
  late List<String> _selected;
  @override void initState() { super.initState(); _selected = List.from(widget.selectedCoupons); }

  void _toggle(String code) {
    setState(() { _selected.contains(code) ? _selected.remove(code) : _selected.add(code); });
    widget.onToggle(code);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            const Text('Купоны', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () => Navigator.of(context).pop(),
              child: const Text('Готово', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600))),
          ])),
        Expanded(child: widget.groups.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : ListView(controller: ctrl, children: [
              ...widget.groups.map((group) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(group.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(spacing: 8, runSpacing: 8,
                    children: group.codes.map((code) {
                      final isChecked = _selected.contains(code);
                      final canApply  = widget.couponLikelyApplies(code);
                      return GestureDetector(onTap: () => _toggle(code),
                        child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isChecked
                                ? (canApply ? const Color(0xFF4CAF50) : Colors.grey.shade400)
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isChecked ? Colors.transparent
                                : (canApply ? Colors.grey.shade300 : Colors.grey.shade200)),
                          ),
                          child: Text(code, style: TextStyle(fontSize: 13,
                            fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                            color: isChecked ? Colors.white
                                : (canApply ? Colors.black87 : Colors.grey.shade400)))));
                    }).toList())),
                Divider(color: Colors.grey.shade100, height: 20),
              ])),
              const SizedBox(height: 20),
            ])),
      ]),
    );
  }
}

// -------------------------------------------------------
// Чип купона в списке применённых
// -------------------------------------------------------
class _CouponChip extends StatelessWidget {
  const _CouponChip({required this.code, required this.isActive, required this.onRemove});
  final String code; final bool isActive; final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? const Color(0xFF4CAF50) : Colors.grey.shade300),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: isActive ? const Color(0xFF2E7D32) : Colors.grey.shade500)),
        const SizedBox(width: 4),
        GestureDetector(onTap: onRemove,
          child: Icon(Icons.close, size: 14, color: isActive ? const Color(0xFF4CAF50) : Colors.grey.shade400)),
      ]),
    );
  }
}

// ── Стандартные виджеты (без изменений) ──────────────────

class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({required this.number, required this.title, required this.child});
  final int number; final String title; final Widget child;
  @override State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}
class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = true;
  @override Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.only(bottom: 8), color: Colors.white,
      child: Column(children: [
        InkWell(onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Text('${widget.number}  ${widget.title}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey.shade500),
            ]))),
        if (_expanded) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: widget.child),
      ]));
  }
}

class _ZoneCheckbox extends StatelessWidget {
  const _ZoneCheckbox({required this.label, required this.price, required this.selected, required this.onTap});
  final String label, price; final bool selected; final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(width: 18, height: 18,
          decoration: BoxDecoration(color: selected ? const Color(0xFF4CAF50) : Colors.white,
            border: Border.all(color: selected ? const Color(0xFF4CAF50) : Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
          child: selected ? const Icon(Icons.check, size: 12, color: Colors.white) : null),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(price, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ])));
  }
}

class _PhoneField extends StatefulWidget {
  const _PhoneField({required this.controller});
  final TextEditingController controller;
  @override State<_PhoneField> createState() => _PhoneFieldState();
}
class _PhoneFieldState extends State<_PhoneField> {
  bool _internal = false;
  @override void initState() { super.initState(); widget.controller.addListener(_onChanged); if (widget.controller.text.isEmpty) _setDigits(''); }
  @override void dispose() { widget.controller.removeListener(_onChanged); super.dispose(); }
  void _setDigits(String d) {
    if (d.length > 10) d = d.substring(0, 10);
    final b = StringBuffer('+7 (');
    for (int i = 0; i < d.length && i < 3; i++) b.write(d[i]);
    if (d.length >= 3) { b.write(') '); for (int i = 3; i < d.length && i < 6; i++) b.write(d[i]); }
    if (d.length >= 6) { b.write(' '); for (int i = 6; i < d.length && i < 8; i++) b.write(d[i]); }
    if (d.length >= 8) { b.write(' '); for (int i = 8; i < d.length && i < 10; i++) b.write(d[i]); }
    final t = b.toString();
    _internal = true;
    widget.controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _internal = false;
  }
  void _onChanged() {
    if (_internal) return;
    var r = widget.controller.text.replaceAll(RegExp(r'[^\d]'), '');
    if (r.startsWith('7') || r.startsWith('8')) r = r.substring(1);
    _setDigits(r);
  }
  @override Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 16),
      child: TextField(controller: widget.controller, keyboardType: TextInputType.phone,
        decoration: InputDecoration(hintText: '+7 (___) ___ __ __', hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: const Color(0xFFF5F5F5), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))));
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.hint, this.required = false});
  final String label; final String? hint; final bool required;
  @override Widget build(BuildContext context) {
    return Row(children: [
      if (required) const Text('* ', style: TextStyle(color: Colors.red, fontSize: 14)),
      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      if (hint != null) ...[const SizedBox(width: 6), Text(hint!, style: TextStyle(fontSize: 12, color: Colors.grey.shade400))],
    ]);
  }
}
