import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/cart/models/cart_model.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:offlinesvet/checkout/order_data_service.dart';

// -------------------------------------------------------
// Аргументы экрана
// -------------------------------------------------------
class CheckoutScreenArgs {
  final Cart cart;
  final Map<String, Product> productsCache;
  const CheckoutScreenArgs({required this.cart, required this.productsCache});
}

// -------------------------------------------------------
// ID свойств Bitrix — DB-схема, не меняется
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
const _pProjectLegal  = 260;
const _pCategoryLegal = 222;
const _pStatusLegal   = 161;
const _pPlaceLegal    = 223;
const _pSourceLegal   = 221;
const _pAreaLegal     = 250;
const _pObjTypeLegal  = 248;
const _pManagerLegal  = 149;

// Место обслуживания — из свойства 124 (физ) / 223 (юр)
// Но значения одинаковые, захардкодим как fallback
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

  // Данные с сервера
  OrderData? _od;
  bool _dataLoading = true;
  String? _dataError;

  bool _isLegal     = false;
  int  _deliveryId  = 25;

  // Выбранные доп. услуги доставки (id -> bool)
  final Set<int> _selectedExtras = {};

  final _extraServiceCtrl = TextEditingController(); // для доп. услуг (id=17)
  final _nameCtrl         = TextEditingController();
  final _phoneCtrl        = TextEditingController();
  final _projectCtrl      = TextEditingController();
  final _areaCtrl         = TextEditingController();
  final _companyCtrl      = TextEditingController();
  final _couponCtrl       = TextEditingController();

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

  // -------------------------------------------------------
  // Геттеры — данные из OrderData с fallback
  // -------------------------------------------------------
  List<DeliveryService> get _deliveries =>
      _od?.deliveries ?? const [];

  List<DeliveryExtraService> get _currentExtras =>
      _od?.extrasForDelivery(_deliveryId) ?? const [];

  List<String> _names(int propId) =>
      _od?.variantNames(propId) ?? const [];

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

  List<String> get _sources =>
      _names(_isLegal ? _pSourceLegal : _pSource);

  List<String> get _catList =>
      _names(_isLegal ? _pCategoryLegal : _pCategory);

  List<String> get _objTypes =>
      _names(_isLegal ? _pObjTypeLegal : _pObjType);

  List<String> get _managers =>
      _names(_isLegal ? _pManagerLegal : _pManager);

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
        final name  = client['NAME']?.toString()  ?? '';
        final phone = client['PHONE']?.toString() ?? '';
        if (name.isNotEmpty)  _nameCtrl.text  = name;
        if (phone.isNotEmpty) _phoneCtrl.text  = _formatPhone(phone);
      }
    }
    _loadOrderData();
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
    } catch (e) {
      if (!mounted) return;
      setState(() { _dataError = e.toString(); _dataLoading = false; });
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
                     _projectCtrl, _areaCtrl, _companyCtrl, _couponCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------
  // Цены
  // -------------------------------------------------------
  double _unitPrice(CartItem item) {
    final p = _productsCache[item.productId.toString()];
    if (p == null || p.prices.isEmpty) return 0;
    return p.prices.map((x) => x.price).reduce((a, b) => a < b ? a : b);
  }

  double get _totalProducts =>
      _cart.items.fold(0.0, (s, i) => s + _unitPrice(i) * i.quantity);

  double get _deliveryCost {
    if (_deliveryId == 32) return 10000; // Примерка — фикс
    if (_deliveryId == 17) return double.tryParse(_extraServiceCtrl.text.trim()) ?? 0;
    // Для зон и остальных — сумма выбранных доп. услуг
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
  // Отправка заказа
  // -------------------------------------------------------
  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) { setState(() => _error = 'Укажите имя клиента'); return; }
    if (_phoneCtrl.text.trim().isEmpty) { setState(() => _error = 'Укажите телефон'); return; }
    if (!_isLegal && _clientType == null) { setState(() => _error = 'Выберите тип клиента'); return; }

    setState(() { _loading = true; _error = null; });

    try {
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) throw Exception('Не удалось определить менеджера');

      final props = _isLegal ? {
        '$_pCompany'     : _companyCtrl.text.trim(),
        '$_pContactName' : _nameCtrl.text.trim(),
        '$_pPhoneLegal'  : _phoneCtrl.text.trim(),
        '$_pProjectLegal': _projectCtrl.text.trim(),
        '$_pCategoryLegal': _categories,
        '$_pStatusLegal' : _orderStatus,
        '$_pPlaceLegal'  : _servicePlace,
        '$_pSourceLegal' : _clientSource,
        '$_pAreaLegal'   : _areaCtrl.text.trim(),
        '$_pObjTypeLegal': _objectType,
        '$_pManagerLegal': _manager,
      } : {
        '$_pNamePhys'  : _nameCtrl.text.trim(),
        '$_pPhonePhys' : _phoneCtrl.text.trim(),
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
          'props'        : props,
        }),
        options: Options(contentType: 'application/json', responseType: ResponseType.plain),
      );

      final result = jsonDecode(response.data as String) as Map<String, dynamic>;

      if (result['success'] == true) {
        final orderId = result['order_id'];
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Заказ оформлен!'),
            content: Text('Заказ №$orderId успешно создан.'),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamedAndRemoveUntil('/products-list', (_) => false);
                },
                child: const Text('В каталог'),
              ),
            ],
          ),
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
        appBar: AppBar(title: const Text('Оформление заказа')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const AppBottomNavBar(currentTab: null),
      );
    }

    if (_dataError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Оформление заказа')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_dataError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () { setState(() { _dataLoading = true; _dataError = null; }); _loadOrderData(); },
              child: const Text('Повторить'),
            ),
          ]),
        ),
        bottomNavigationBar: const AppBottomNavBar(currentTab: null),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        // Стрелка назад — возврат в корзину
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // Поиск — компактный, не на всю ширину
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.qr_code_scanner),
            const SizedBox(width: 12),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildCouponBlock(),
          _CollapsibleSection(number: 1, title: 'Товары в заказе', child: _buildProductList()),
          _CollapsibleSection(number: 2, title: 'Тип плательщика', child: _buildToggle(
            options: ['Физическое лицо', 'Юридическое лицо'],
            selected: _isLegal ? 1 : 0,
            onChanged: (i) => setState(() => _isLegal = i == 1),
          )),
          _CollapsibleSection(number: 3, title: 'Доставка', child: _buildDeliveryBlock()),
          _CollapsibleSection(number: 4, title: 'Оплата', child: _buildPaymentBlock()),
          _CollapsibleSection(number: 5, title: 'Покупатель', child: _buildBuyerForm()),
          _buildTotalBlock(),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          // Нижняя панель — передаём null чтобы кнопка корзины была кликабельной
          // и нажатие на неё возвращало назад в мультикорзину через pop
          AppBottomNavBar(
            currentTab: null,
            onCartTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // Купоны
  // -------------------------------------------------------
  Widget _buildCouponBlock() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Купоны', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _couponCtrl,
          decoration: InputDecoration(
            hintText: 'Применить купон',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true, fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ]),
    );
  }

  // -------------------------------------------------------
  // Товары
  // -------------------------------------------------------
  Widget _buildProductList() {
    return Column(children: _cart.items.map((item) {
      final product = _productsCache[item.productId.toString()];
      final price = _unitPrice(item) * item.quantity;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 72, height: 72,
            child: ClipRRect(borderRadius: BorderRadius.circular(8),
              child: product?.image != null
                  ? CachedNetworkImage(imageUrl: product!.image!, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey.shade100),
                      errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: Colors.grey))
                  : Container(color: Colors.grey.shade100,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product?.name ?? 'Товар #${item.productId}',
              style: const TextStyle(fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            if (item.rasprodazha.isNotEmpty && item.rasprodazha != 'Без скидки') ...[
              Text('Распродажа', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              Text(item.rasprodazha, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmt(price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('${item.quantity} шт', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
        ]),
      );
    }).toList());
  }

  // -------------------------------------------------------
  // Горизонтальный переключатель
  // -------------------------------------------------------
  Widget _buildToggle({
    required List<String> options,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
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

  // -------------------------------------------------------
  // Доставка — динамически из OrderData
  // -------------------------------------------------------
  Widget _buildDeliveryBlock() {
    final deliveries = _deliveries;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Сетка вариантов 2×2
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: deliveries.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 3.2,
          crossAxisSpacing: 8, mainAxisSpacing: 8,
        ),
        itemBuilder: (_, i) {
          final d = deliveries[i];
          final isSelected = d.id == _deliveryId;
          return GestureDetector(
            onTap: () => setState(() { _deliveryId = d.id; _selectedExtras.clear(); }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(d.name, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13,
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      // Детали выбранной службы
      _buildDeliveryDetails(),
    ]);
  }

  Widget _buildDeliveryDetails() {
    final extras = _currentExtras;
    final selectedDelivery = _deliveries.where((d) => d.id == _deliveryId).firstOrNull;
    if (selectedDelivery == null) return const SizedBox.shrink();

    // Примерка (id=32) — фиксированная стоимость 10 000
    if (_deliveryId == 32) {
      return _buildInfoBlock(
        title: selectedDelivery.name,
        description: selectedDelivery.description,
        cost: 10000,
        costColor: Colors.red,
      );
    }

    // Авиадоставка (id=33)
    if (_deliveryId == 33) {
      return _buildInfoBlock(
        title: selectedDelivery.name,
        description: selectedDelivery.description.isNotEmpty
            ? selectedDelivery.description
            : 'Срок доставки: от 5 до 18 дней',
        cost: 0,
      );
    }

    // Дополнительные услуги (id=17) — поле ввода суммы
    if (_deliveryId == 17) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(selectedDelivery.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (selectedDelivery.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(selectedDelivery.description,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _extraServiceCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Сумма за установку (₸)',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          _costRow(_deliveryCost),
        ]),
      );
    }

    // Доставка по зонам (id=25) и другие с доп. услугами
    if (extras.isEmpty) return const SizedBox.shrink();

    // Разбиваем на 2 колонки: левые 4, правые остальные
    final leftExtras  = extras.length > 4 ? extras.sublist(0, 4) : extras;
    final rightExtras = extras.length > 4 ? extras.sublist(4) : <DeliveryExtraService>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(selectedDelivery.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text('Стоимость  ${_fmt(_deliveryCost)}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: leftExtras.map((e) => _ZoneCheckbox(
            label: e.name, price: _fmt(e.price),
            selected: _selectedExtras.contains(e.id),
            onTap: () => setState(() {
              _selectedExtras.contains(e.id) ? _selectedExtras.remove(e.id) : _selectedExtras.add(e.id);
            }),
          )).toList())),
          if (rightExtras.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(child: Column(children: rightExtras.map((e) => _ZoneCheckbox(
              label: e.name, price: _fmt(e.price),
              selected: _selectedExtras.contains(e.id),
              onTap: () => setState(() {
                _selectedExtras.contains(e.id) ? _selectedExtras.remove(e.id) : _selectedExtras.add(e.id);
              }),
            )).toList())),
          ],
        ]),
      ]),
    );
  }

  Widget _buildInfoBlock({
    required String title, required String description,
    required double cost, Color? costColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        ],
        const SizedBox(height: 8),
        _costRow(cost, color: costColor),
      ]),
    );
  }

  Widget _costRow(double cost, {Color? color}) {
    return Row(children: [
      Text('Стоимость:', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(width: 8),
      Text(_fmt(cost), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? Colors.black87)),
    ]);
  }

  // -------------------------------------------------------
  // Оплата
  // -------------------------------------------------------
  Widget _buildPaymentBlock() {
    return FilledButton(
      onPressed: null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF4CAF50),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        disabledBackgroundColor: const Color(0xFF4CAF50),
        disabledForegroundColor: Colors.white,
      ),
      child: const Text('Оплата QR кодом Каспи', style: TextStyle(fontSize: 15)),
    );
  }

  // -------------------------------------------------------
  // Форма покупателя
  // -------------------------------------------------------
  Widget _buildBuyerForm() {
    final statusIdx = _statuses.indexWhere((s) => s['value'] == _orderStatus);
    final placeIdx  = _places.indexOf(_servicePlace);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!_isLegal) ...[
        _FieldLabel(label: 'Тип клиента', required: true),
        const SizedBox(height: 6),
        _buildToggle(
          options: _clientTypes,
          selected: _clientTypes.indexOf(_clientType ?? '').clamp(0, _clientTypes.length - 1),
          onChanged: (i) => setState(() => _clientType = _clientTypes[i]),
        ),
        const SizedBox(height: 16),
      ],

      _FieldLabel(label: 'Название проекта/объекта', required: true),
      const SizedBox(height: 6),
      _buildTextField(_projectCtrl),
      const SizedBox(height: 16),

      _FieldLabel(label: 'Категории товаров', required: true),
      const SizedBox(height: 6),
      _buildCheckboxGrid(
        items: _catList, selected: _categories,
        onToggle: (v) => setState(() => _categories.contains(v) ? _categories.remove(v) : _categories.add(v)),
      ),
      const SizedBox(height: 16),

      _FieldLabel(label: 'Состояние заказа', required: true),
      Text('Присвоение статуса заказа после его оформления',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      const SizedBox(height: 6),
      _buildToggle(
        options: _statuses.map((s) => s['label']!).toList(),
        selected: statusIdx < 0 ? 0 : statusIdx,
        onChanged: (i) => setState(() => _orderStatus = _statuses[i]['value']!),
      ),
      const SizedBox(height: 16),

      _FieldLabel(label: 'Место обслуживания клиента', required: true),
      const SizedBox(height: 6),
      _buildToggle(
        options: _places,
        selected: placeIdx < 0 ? 0 : placeIdx,
        onChanged: (i) => setState(() => _servicePlace = _places[i]),
      ),
      const SizedBox(height: 16),

      _FieldLabel(
        label: _isLegal ? 'Источник клиента для салонов 2025' : 'Источник клиента для салонов 2026',
        hint: 'Откуда клиент узнал о компании', required: true,
      ),
      const SizedBox(height: 6),
      _buildSelectGrid(items: _sources, selected: _clientSource,
        onSelect: (v) => setState(() => _clientSource = v)),
      const SizedBox(height: 16),

      _FieldLabel(label: _isLegal ? 'ФИО контактного лица' : 'Имя клиента', required: true),
      const SizedBox(height: 6),
      _buildTextField(_nameCtrl),
      const SizedBox(height: 16),

      _FieldLabel(label: 'Телефон клиента', required: true),
      const SizedBox(height: 6),
      _PhoneField(controller: _phoneCtrl),

      _FieldLabel(label: 'Площадь объекта (квадратура)', required: true),
      const SizedBox(height: 6),
      _buildTextField(_areaCtrl, keyboardType: TextInputType.number),
      const SizedBox(height: 16),

      _FieldLabel(label: 'Тип объекта', required: true),
      const SizedBox(height: 6),
      _buildCheckboxGrid(
        items: _objTypes, selected: _objectType != null ? [_objectType!] : [],
        singleSelect: true,
        onToggle: (v) => setState(() => _objectType = _objectType == v ? null : v),
      ),
      const SizedBox(height: 16),

      if (_isLegal) ...[
        _FieldLabel(label: 'Наименование компании', required: true),
        const SizedBox(height: 6),
        _buildTextField(_companyCtrl),
        const SizedBox(height: 16),
      ],

      _FieldLabel(label: 'Менеджер клиента', required: true),
      const SizedBox(height: 6),
      _buildSelectGrid(items: _managers, selected: _manager,
        onSelect: (v) => setState(() => _manager = v)),
    ]);
  }

  // -------------------------------------------------------
  // Итог
  // -------------------------------------------------------
  Widget _buildTotalBlock() {
    final delivery = _deliveryCost;
    final total = _totalProducts + delivery;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Товаров на', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          Text(_fmt(_totalProducts), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ])),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Доставка', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          Text(delivery == 0 ? 'бесплатно' : _fmt(delivery),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Итого', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          Text(_fmt(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  // -------------------------------------------------------
  // Строительные блоки UI
  // -------------------------------------------------------
  Widget _buildTextField(TextEditingController ctrl,
      {String? hint, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: TextField(
        controller: ctrl, keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildCheckboxGrid({
    required List<String> items, required List<String> selected,
    required ValueChanged<String> onToggle, bool singleSelect = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cols = singleSelect ? 1 : 2;
    final ratio = singleSelect ? 7.0 : 4.0;
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, childAspectRatio: ratio,
        crossAxisSpacing: 0, mainAxisSpacing: 0,
      ),
      itemBuilder: (_, i) {
        final item = items[i];
        final isSelected = selected.contains(item);
        return GestureDetector(onTap: () => onToggle(item),
          child: Row(children: [
            Container(width: 20, height: 20,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4CAF50) : Colors.white,
                border: Border.all(color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
            const SizedBox(width: 8),
            Expanded(child: Text(item, style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis, maxLines: 2)),
          ]),
        );
      },
    );
  }

  Widget _buildSelectGrid({
    required List<String> items, required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 3.5,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final item = items[i];
        final isSelected = item == selected;
        return GestureDetector(onTap: () => onSelect(item),
          child: AnimatedContainer(duration: const Duration(milliseconds: 120),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(item, style: TextStyle(fontSize: 13,
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
              overflow: TextOverflow.ellipsis, maxLines: 2)));
      },
    );
  }
}

// -------------------------------------------------------
// Сворачиваемая секция
// -------------------------------------------------------
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({required this.number, required this.title, required this.child});
  final int number;
  final String title;
  final Widget child;
  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = true;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), color: Colors.white,
      child: Column(children: [
        InkWell(onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Text('${widget.number}  ${widget.title}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.grey.shade500),
            ]))),
        if (_expanded)
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: widget.child),
      ]),
    );
  }
}

// -------------------------------------------------------
// Чекбокс зоны доставки
// -------------------------------------------------------
class _ZoneCheckbox extends StatelessWidget {
  const _ZoneCheckbox({required this.label, required this.price,
    required this.selected, required this.onTap});
  final String label, price;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 18, height: 18,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF4CAF50) : Colors.white,
              border: Border.all(color: selected ? const Color(0xFF4CAF50) : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: selected ? const Icon(Icons.check, size: 12, color: Colors.white) : null),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(price, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ])));
  }
}

// -------------------------------------------------------
// Поле телефона с маской
// -------------------------------------------------------
class _PhoneField extends StatefulWidget {
  const _PhoneField({required this.controller});
  final TextEditingController controller;
  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  bool _internal = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.controller.text.isEmpty) _setDigits('');
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _setDigits(String digits) {
    if (digits.length > 10) digits = digits.substring(0, 10);
    final buf = StringBuffer('+7 (');
    for (int i = 0; i < digits.length && i < 3; i++) buf.write(digits[i]);
    if (digits.length >= 3) { buf.write(') '); for (int i = 3; i < digits.length && i < 6; i++) buf.write(digits[i]); }
    if (digits.length >= 6) { buf.write(' '); for (int i = 6; i < digits.length && i < 8; i++) buf.write(digits[i]); }
    if (digits.length >= 8) { buf.write(' '); for (int i = 8; i < digits.length && i < 10; i++) buf.write(digits[i]); }
    final text = buf.toString();
    _internal = true;
    widget.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _internal = false;
  }

  void _onChanged() {
    if (_internal) return;
    var raw = widget.controller.text.replaceAll(RegExp(r'[^\d]'), '');
    if (raw.startsWith('7') || raw.startsWith('8')) raw = raw.substring(1);
    _setDigits(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 16),
      child: TextField(controller: widget.controller, keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          hintText: '+7 (___) ___ __ __',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        )));
  }
}

// -------------------------------------------------------
// Метка поля
// -------------------------------------------------------
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.hint, this.required = false});
  final String label;
  final String? hint;
  final bool required;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (required) const Text('* ', style: TextStyle(color: Colors.red, fontSize: 14)),
      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      if (hint != null) ...[
        const SizedBox(width: 6),
        Text(hint!, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ],
    ]);
  }
}
