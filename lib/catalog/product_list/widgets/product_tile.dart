import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:offlinesvet/cart/view/add_to_cart_sheet.dart';

final _unescape = HtmlUnescape();

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product});
  final Product product;

  double get _price {
    if (product.prices.isEmpty) return 0;
    return product.prices
        .map((p) => p.price)
        .reduce((a, b) => a < b ? a : b);
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/products-item', arguments: product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -----------------------------------------------
            // Картинка
            // -----------------------------------------------
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(
                  width: double.infinity,
                  child: product.image != null && product.image!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.image!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.grey,
                            ),
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
            ),

            // -----------------------------------------------
            // Текстовая часть
            // -----------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Цена
                  if (_price > 0)
                    Text(
                      _fmt(_price),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  const SizedBox(height: 4),

                  // Название
                  Text(
                    _unescape.convert(product.name),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // -----------------------------------------------
            // Три иконки внизу
            // -----------------------------------------------
            Row(
              children: [
                // Корзина
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                    color: Colors.black54,
                    onPressed: () => showAddToCartSheet(context, product),
                  ),
                ),
                // Избранное (заглушка)
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.favorite_border, size: 20),
                    color: Colors.black54,
                    onPressed: () {},
                  ),
                ),
                // Ещё (заглушка)
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.menu, size: 20),
                    color: Colors.black54,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
