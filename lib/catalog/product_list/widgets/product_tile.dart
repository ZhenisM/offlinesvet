import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:offlinesvet/cart/view/add_to_cart_sheet.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
  });

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        Navigator.of(context).pushNamed(
          '/products-item',
          arguments: product,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.black12),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🖼 КАРТИНКА (25%)
            SizedBox(
              width: 90,
              height: 90,
              child: product.image != null && product.image!.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: product.image!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.grey,
                ),
              )
                  : const Icon(Icons.image_not_supported),
            ),

            const SizedBox(width: 10),

            /// 📦 ПРАВАЯ ЧАСТЬ
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// 🔹 БРЕНД + ФАСОВКА
                  Row(
                    children: [
                      if (product.brend != null)
                        _chip(
                          product.brend!,
                          const Color(0xFFFEE4A5),
                        ),

                      const SizedBox(width: 6),
                    ],
                  ),

                  const SizedBox(height: 6),

                  /// 🔹 НАЗВАНИЕ
                  Text(
                    HtmlUnescape().convert(product.name),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  /// 🔹 АРТИКУЛ + КНОПКА
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              'Артикул: ${product.article ?? ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: 4),

                            /// 📋 КОПИРОВАНИЕ
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: product.article ?? ''),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Артикул скопирован'),
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.copy,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// 🛒 КНОПКА
                      TextButton(
                        onPressed: () => showAddToCartSheet(context, product),
                        child: const Text('В корзину'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 ЧИП
  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
