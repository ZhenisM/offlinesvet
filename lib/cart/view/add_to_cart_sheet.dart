import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/cart/cart_api_service.dart';
import 'package:offlinesvet/cart/models/cart_model.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';

/// Список помещений для SELECT_ROOM — взят из реальных данных корзин на сервере.
const _kRooms = [
  'без значения',
  'Гостиная',
  'Спальня',
  'Кухня',
  'Детская',
  'Прихожая',
  'Санузел',
  'Холл',
];

/// Список вариантов распродажи для _RASPRODAZHA.
/// Значение передаётся в PROPS корзины как есть и используется
/// при оформлении заказа для применения купона.
const _kSaleOptions = [
  'Без скидки',
  'Распродажа 10%',
  'Распродажа 20%',
  'Распродажа 30%',
  'Распродажа 40%',
  'Распродажа 50%',
  'Распродажа 60%',
  'Распродажа 70%',
  'Распродажа 80%',
];

/// Открывает bottom sheet добавления товара в корзину.
/// Возвращает true если товар был успешно добавлен.
Future<bool> showAddToCartSheet(
  BuildContext context,
  Product product,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddToCartSheet(product: product),
  );
  return result == true;
}

class _AddToCartSheet extends StatefulWidget {
  const _AddToCartSheet({required this.product});
  final Product product;

  @override
  State<_AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<_AddToCartSheet> {
  final _cartApiService = CartApiService(dio: Dio());

  String _selectedRoom = _kRooms.first;
  String _selectedSale = _kSaleOptions.first;
  int _quantity = 1;
  bool _loading = false;
  String? _error;

  /// Базовая цена (минимальная из всех типов цен).
  double get _basePrice {
    if (widget.product.prices.isEmpty) return 0;
    return widget.product.prices
        .map((p) => p.price)
        .reduce((a, b) => a < b ? a : b);
  }

  /// Форматирование цены в виде "120 000 ₸"
  String _formatPrice(double price) {
    final parts = price.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(parts[i]);
    }
    return '${buffer.toString()} ₸';
  }

  Future<void> _addToCart() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) {
        setState(() {
          _error = 'Не удалось определить менеджера';
          _loading = false;
        });
        return;
      }

      // Загружаем текущие корзины, чтобы найти IS_CURRENT
      final carts = await _cartApiService.loadCarts(managerId: managerId);
      final currentCart = carts.firstWhere(
        (c) => c.isCurrent,
        orElse: () => throw Exception('Нет текущей корзины. Сначала выберите клиента.'),
      );

      // Формируем обновлённый список товаров
      final newItem = CartItem(
        productId: int.parse(widget.product.id),
        quantity: _quantity,
        selectRoom: _selectedRoom,
        rasprodazha: _selectedSale,
      );

      final updatedItems = [...currentCart.items, newItem];

      await _cartApiService.updateCartItems(
        basketId: currentCart.id,
        items: updatedItems,
      );

      debugPrint('ADD TO CART: успешно добавлен товар ${widget.product.id} в корзину ${currentCart.id}');
      debugPrint('ADD TO CART: productsInfo = ${encodeCartItems(updatedItems)}');

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final product = widget.product;

    return SafeArea(
      child: Container(
        height: screenHeight * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Хвостик
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

            // Карточка товара
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Картинка ~18% ширины
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.18,
                    height: 72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: product.image != null && product.image!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: product.image!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.grey.shade100,
                              ),
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
                  // Цена и название
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatPrice(_basePrice),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Выборы
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(label: 'Помещение'),
                    const SizedBox(height: 8),
                    _Dropdown(
                      value: _selectedRoom,
                      items: _kRooms,
                      onChanged: (v) => setState(() => _selectedRoom = v),
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel(label: 'Распродажа'),
                    const SizedBox(height: 8),
                    _Dropdown(
                      value: _selectedSale,
                      items: _kSaleOptions,
                      onChanged: (v) => setState(() => _selectedSale = v),
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel(label: 'Количество'),
                    const SizedBox(height: 8),
                    // Степпер количества
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: _quantity > 1
                                ? () => setState(() => _quantity--)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.remove,
                                size: 20,
                                color: _quantity > 1
                                    ? Colors.black87
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '$_quantity',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _quantity++),
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.add, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Кнопка
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton(
                onPressed: _loading ? null : _addToCart,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF4CAF50),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Добавить в корзину',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: Colors.grey.shade500,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
