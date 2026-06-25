import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart' show NoInternetException;
import 'package:offlinesvet/cart/cart_api_service.dart';
import 'package:offlinesvet/cart/models/cart_model.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/common/menu/menu_screen.dart';
import 'package:offlinesvet/customer/customer.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/checkout/checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cartApiService = CartApiService(dio: Dio());
  final _productsRepository = ProductsRepository(dio: Dio());

  List<Cart>? _carts;
  String? _error;
  List<Section>? _sections;
  // Кэш товаров по productId для отображения в корзине
  Map<String, Product> _productsCache = {};
  bool _productsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCarts();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final sections = await _productsRepository.getSections();
      if (!mounted) return;
      setState(() => _sections = sections);
    } catch (_) {}
  }

  void _menuOpen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: _sections ?? const [],
          products: const [],
        ),
      ),
    );
  }

  Future<void> _loadCarts() async {
    setState(() {
      _error = null;
    });

    final managerId = await CustomerStorage.currentManagerId();
    if (managerId == null) {
      setState(() => _error = 'Не удалось определить менеджера');
      return;
    }

    try {
      final carts = await _cartApiService.loadCarts(managerId: managerId);
      if (!mounted) return;
      setState(() => _carts = carts);
      // Загружаем товары ВСЕХ корзин сразу — чтобы в sheet выбора
      // корзины цены были видны сразу для всех, а не только текущей.
      _loadProductsForAllCarts(carts);
    } on NoInternetException {
      if (!mounted) return;
      setState(() => _error = 'Нет интернета');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить корзины');
    }
  }

  /// Загружает данные товаров для ВСЕХ корзин менеджера одним запросом.
  /// Это нужно чтобы в sheet выбора корзины цены были видны сразу у всех
  /// карточек, а не только у текущей.
  Future<void> _loadProductsForAllCarts(List<Cart> carts) async {
    // Собираем уникальные ID товаров из всех корзин
    final allIds = carts
        .expand((cart) => cart.items)
        .map((item) => item.productId.toString())
        .toSet()
        .toList();

    if (allIds.isEmpty) return;

    // Убираем уже загруженные
    final missingIds = allIds
        .where((id) => !_productsCache.containsKey(id))
        .toList();
    if (missingIds.isEmpty) return;

    setState(() => _productsLoading = true);

    try {
      final products = await _productsRepository.getProductsByIds(missingIds);
      if (!mounted) return;
      setState(() {
        for (final p in products) {
          _productsCache[p.id] = p;
        }
        _productsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _productsLoading = false);
    }
  }

  // Оставляем метод для загрузки после переключения корзины
  Future<void> _loadProductsForCurrentCart(List<Cart> carts) async {
    final current = _currentCartFrom(carts);
    if (current == null || current.items.isEmpty) return;

    final ids = current.items
        .map((item) => item.productId.toString())
        .toSet()
        .toList();

    final missingIds = ids
        .where((id) => !_productsCache.containsKey(id))
        .toList();
    if (missingIds.isEmpty) return;

    setState(() => _productsLoading = true);

    try {
      final products = await _productsRepository.getProductsByIds(missingIds);
      if (!mounted) return;
      setState(() {
        for (final p in products) {
          _productsCache[p.id] = p;
        }
        _productsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _productsLoading = false);
    }
  }

  Cart? get _currentCart => _currentCartFrom(_carts ?? []);

  Cart? _currentCartFrom(List<Cart> carts) {
    if (carts.isEmpty) return null;
    for (final cart in carts) {
      if (cart.isCurrent) return cart;
    }
    return carts.first;
  }

  Future<void> _switchCart(Cart cart) async {
    if (cart.isCurrent) return;

    final managerId = await CustomerStorage.currentManagerId();
    if (managerId == null) return;

    try {
      await _cartApiService.setCurrentCart(
        basketId: cart.id,
        managerId: managerId,
      );
      if (cart.clientInfo != null) {
        final customer = Customer.fromMultibasketsClientInfo(
          cart.clientInfo!,
          selectedAt: DateTime.now(),
        );
        await CustomerStorage.setActive(customer);
      }
      await _loadCarts();
    } catch (e) {
      setState(() => _error = 'Не удалось переключить корзину');
    }
  }

  Future<bool> _deleteCartOnServer(Cart cart) async {
    try {
      await _cartApiService.setCartStatus(
        basketId: cart.id,
        status: CartStatus.deleted,
      );
      return true;
    } catch (e) {
      setState(() => _error = 'Не удалось удалить корзину');
      return false;
    }
  }

  Future<void> _clearCart() async {
    final current = _currentCart;
    if (current == null || current.items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить корзину?'),
        content: const Text('Все товары из текущей корзины будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _cartApiService.updateCartItems(
        basketId: current.id,
        items: [],
      );
      await _loadCarts();
    } catch (e) {
      setState(() => _error = 'Не удалось очистить корзину');
    }
  }

  Future<void> _removeItem(CartItem item) async {
    final current = _currentCart;
    if (current == null) return;

    // Ищем по значениям полей, а не по ссылке на объект
    final items = List<CartItem>.from(current.items);
    final idx = items.indexWhere((i) =>
        i.productId == item.productId &&
        i.selectRoom == item.selectRoom &&
        i.rasprodazha == item.rasprodazha);

    debugPrint('_removeItem: productId=${item.productId} idx=$idx total=${items.length}');

    if (idx < 0) {
      setState(() => _error = 'Товар не найден в корзине');
      return;
    }
    items.removeAt(idx);

    try {
      await _cartApiService.updateCartItems(
        basketId: current.id,
        items: items,
      );
      await _loadCarts();
    } catch (e) {
      debugPrint('_removeItem error: $e');
      setState(() => _error = 'Не удалось удалить товар');
    }
  }

  Future<void> _updateItemQuantity(CartItem item, int delta) async {
    final current = _currentCart;
    if (current == null) return;

    final newQty = item.quantity + delta;
    if (newQty < 1) {
      await _removeItem(item);
      return;
    }

    final updated = current.items.map((i) {
      if (i.productId == item.productId &&
              i.selectRoom == item.selectRoom &&
              i.rasprodazha == item.rasprodazha) {
        return CartItem(
          productId: i.productId,
          quantity: newQty,
          selectRoom: i.selectRoom,
          rasprodazha: i.rasprodazha,
        );
      }
      return i;
    }).toList();

    try {
      await _cartApiService.updateCartItems(
        basketId: current.id,
        items: updated,
      );
      await _loadCarts();
    } catch (e) {
      setState(() => _error = 'Не удалось обновить количество');
    }
  }

  Future<void> _openCartSelector() async {
    if (_carts == null || _carts!.isEmpty) return;

    final selected = await showModalBottomSheet<Cart>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartSelectorSheet(
        initialCarts: _carts!,
        productsCache: _productsCache,
        onDelete: _deleteCartOnServer,
      ),
    );

    await _loadCarts();

    if (selected != null) {
      await _switchCart(selected);
    }
  }

  // -------------------------------------------------------
  // Цена корзины
  // -------------------------------------------------------

  double _totalPrice() {
    final current = _currentCart;
    if (current == null || current.items.isEmpty) return 0;

    double total = 0;
    for (final item in current.items) {
      final product = _productsCache[item.productId.toString()];
      if (product != null && product.prices.isNotEmpty) {
        final price = product.prices
            .map((p) => p.price)
            .reduce((a, b) => a < b ? a : b);
        total += price * item.quantity;
      }
    }
    return total;
  }

  String _formatPrice(double price) {
    final parts = price.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(parts[i]);
    }
    return '${buffer.toString()} ₸';
  }

  // -------------------------------------------------------
  // Build
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final current = _currentCart;
    final itemsCount = current?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 0;
    final hasItems = itemsCount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_outlined),
          onPressed: _menuOpen,
        ),
        title: const Text('Мультикорзина'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Плашка "Очистить корзину" — прижата к шапке
          _ClearCartBanner(onTap: _clearCart),

          // Остальное содержимое
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Зелёная кнопка "Продолжить" — только если есть товары
          if (hasItems)
            _ContinueBar(
              itemsCount: itemsCount,
              totalPrice: _formatPrice(_totalPrice()),
              onContinue: () {
                final current = _currentCart;
                if (current == null) return;
                Navigator.of(context).pushNamed(
                  '/checkout',
                  arguments: CheckoutScreenArgs(
                    cart: current,
                    productsCache: Map.from(_productsCache),
                  ),
                );
              },
            ),
          const AppBottomNavBar(currentTab: AppBottomTab.cart),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadCarts,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_carts == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_carts!.isEmpty) {
      return const Center(
        child: Text(
          'У вас пока нет корзин.\nВыберите клиента, чтобы создать новую.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final current = _currentCart;

    return Column(
      children: [
        // Селектор корзины
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildCartSelector(),
        ),

        // Счётчик товаров
        if (current != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              _itemsCountLabel(current.items.fold<int>(0, (s, i) => s + i.quantity)),
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),

        // Список товаров
        Expanded(
          child: current == null || current.items.isEmpty
              ? const Center(
                  child: Text(
                    'Корзина пуста',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : _productsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: current.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final item = current.items[index];
                        final product = _productsCache[item.productId.toString()];
                        return _CartItemTile(
                          item: item,
                          product: product,
                          onDelete: () => _removeItem(item),
                          onIncrement: () => _updateItemQuantity(item, 1),
                          onDecrement: () => _updateItemQuantity(item, -1),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCartSelector() {
    final carts = _carts!;
    final current = _currentCart;

    if (carts.isEmpty) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Нет активных корзин', style: TextStyle(color: Colors.grey)),
      );
    }

    return InkWell(
      onTap: _openCartSelector,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current?.title ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    );
  }

  String _itemsCountLabel(int count) {
    final last = count % 10;
    final lastTwo = count % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return '$count товаров';
    if (last == 1) return '$count товар';
    if (last >= 2 && last <= 4) return '$count товара';
    return '$count товаров';
  }
}

// -------------------------------------------------------
// Плашка "Очистить корзину"
// -------------------------------------------------------

class _ClearCartBanner extends StatelessWidget {
  const _ClearCartBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Text(
          'Очистить корзину',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// Карточка товара в корзине
// -------------------------------------------------------

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.product,
    required this.onDelete,
    required this.onIncrement,
    required this.onDecrement,
  });

  final CartItem item;
  final Product? product;
  final VoidCallback onDelete;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  double get _unitPrice {
    if (product == null || product!.prices.isEmpty) return 0;
    return product!.prices
        .map((p) => p.price)
        .reduce((a, b) => a < b ? a : b);
  }

  double get _totalPrice => _unitPrice * item.quantity;

  String _formatPrice(double price) {
    final parts = price.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(parts[i]);
    }
    return '${buffer.toString()} ₸';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Картинка
              SizedBox(
                width: 80,
                height: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: product?.image != null && product!.image!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product!.image!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: Colors.grey.shade100),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.grey,
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.grey,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Цена + название
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatPrice(_totalPrice),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatPrice(_unitPrice)}/шт',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: product != null
                          ? () => Navigator.of(context).pushNamed(
                                '/products-item',
                                arguments: product,
                              )
                          : null,
                      child: Text(
                        product?.name ?? 'Товар #${item.productId}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Нижняя строка: удалить + степпер
          Row(
            children: [
              IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: Colors.grey.shade500),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const Spacer(),
              // Степпер количества
              Row(
                children: [
                  _StepperButton(
                    icon: Icons.remove,
                    onPressed: onDecrement,
                  ),
                  Container(
                    width: 52,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _StepperButton(
                    icon: Icons.add,
                    onPressed: onIncrement,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: Colors.black87),
      ),
    );
  }
}

// -------------------------------------------------------
// Кнопка "Продолжить"
// -------------------------------------------------------

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({
    required this.itemsCount,
    required this.totalPrice,
    required this.onContinue,
  });

  final int itemsCount;
  final String totalPrice;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final label = itemsCount == 1 ? '1 товар' : '$itemsCount товара';

    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 8, 5, 4),
      child: FilledButton(
        onPressed: onContinue,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  totalPrice,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'Продолжить',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------
// Bottom sheet выбора корзины (без изменений по логике)
// -------------------------------------------------------

class _CartSelectorSheet extends StatefulWidget {
  const _CartSelectorSheet({
    required this.initialCarts,
    required this.productsCache,
    required this.onDelete,
  });

  final List<Cart> initialCarts;
  final Map<String, Product> productsCache;
  final Future<bool> Function(Cart cart) onDelete;

  @override
  State<_CartSelectorSheet> createState() => _CartSelectorSheetState();
}

class _CartSelectorSheetState extends State<_CartSelectorSheet> {
  late List<Cart> _carts;
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _carts = List.of(widget.initialCarts);
  }

  Cart? get _currentCart {
    for (final cart in _carts) {
      if (cart.isCurrent) return cart;
    }
    return _carts.isNotEmpty ? _carts.first : null;
  }

  Future<void> _handleDelete(Cart cart) async {
    setState(() => _deletingIds.add(cart.id));
    final success = await widget.onDelete(cart);
    if (!mounted) return;
    setState(() {
      _deletingIds.remove(cart.id);
      if (success) _carts.removeWhere((c) => c.id == cart.id);
    });
    if (success && _carts.isEmpty && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentCart;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_carts.length} ${_cartsLabel(_carts.length)}',
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: _carts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final cart = _carts[index];
                  final isActive = cart.id == current?.id;
                  return _CartSelectorTile(
                    cart: cart,
                    isActive: isActive,
                    isDeleting: _deletingIds.contains(cart.id),
                    productsCache: widget.productsCache,
                    onTap: () => Navigator.of(context).pop(cart),
                    onDelete: () => _handleDelete(cart),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _cartsLabel(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    if (lastTwo >= 11 && lastTwo <= 14) return 'корзин';
    if (last == 1) return 'корзина';
    if (last >= 2 && last <= 4) return 'корзины';
    return 'корзин';
  }
}

class _CartSelectorTile extends StatelessWidget {
  const _CartSelectorTile({
    required this.cart,
    required this.isActive,
    required this.isDeleting,
    required this.productsCache,
    required this.onTap,
    required this.onDelete,
  });

  final Cart cart;
  final bool isActive;
  final bool isDeleting;
  final Map<String, Product> productsCache;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  double _cartTotal() {
    double total = 0;
    for (final item in cart.items) {
      final product = productsCache[item.productId.toString()];
      if (product != null && product.prices.isNotEmpty) {
        final price = product.prices
            .map((p) => p.price)
            .reduce((a, b) => a < b ? a : b);
        total += price * item.quantity;
      }
    }
    return total;
  }

  String _formatPrice(double price) {
    final parts = price.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(parts[i]);
    }
    return '${buffer.toString()} ₸';
  }

  @override
  Widget build(BuildContext context) {
    final itemsCount = cart.items.length;
    final total = _cartTotal();
    final priceLabel = total > 0 ? _formatPrice(total) : '0 ₸';

    return Material(
      color: isActive ? const Color(0xFF4CAF50) : const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isDeleting ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: isDeleting ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cart.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: isActive ? Colors.white70 : Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        priceLabel,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Позиций $itemsCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: isActive ? Colors.white70 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                isDeleting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          color: isActive ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
