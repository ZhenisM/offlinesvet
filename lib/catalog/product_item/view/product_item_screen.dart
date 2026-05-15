import 'package:flutter/material.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';

class ProductItemScreen extends StatefulWidget {
  const ProductItemScreen({super.key});

  @override
  State<ProductItemScreen> createState() => _ProductItemScreenState();
}

class _ProductItemScreenState extends State<ProductItemScreen> {
  Product? product;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Product) {
      setState(() {
        product = args;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Товар'),
        centerTitle: true,
      ),

      // Кнопка "В корзину" внизу экрана
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () {
              // TODO: добавить в корзину
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Корзина пока недоступна')),
              );
            },
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text('В корзину'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Название товара в теле страницы
          Text(
            product!.name,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Картинка товара
          if (product!.image != null && product!.image!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                product!.image!,
                height: 260,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 260,
                  color: Colors.grey.shade100,
                  child: const Icon(Icons.image_not_supported_outlined,
                      size: 48, color: Colors.grey),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Основная информация
          _InfoRow(label: 'Артикул', value: product!.article ?? '—'),
          if (product!.brend != null) _InfoRow(label: 'Бренд', value: product!.brend!),
          _InfoRow(label: 'ID товара', value: product!.id),
          _InfoRow(label: 'ID категории', value: product!.sectionId),

          const SizedBox(height: 20),

          // Цены
          if (product!.prices.isNotEmpty) ...[
            Text(
              'Цены',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...product!.prices.map(
                  (price) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(price.typeName,
                        style: const TextStyle(color: Colors.grey)),
                    Text(
                      '${price.price.toStringAsFixed(0)} ${price.currency}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Свойства товара — развёртывающийся блок
          if (product!.props.isNotEmpty)
            _PropsExpansionTile(props: product!.props),

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// Строка с меткой и значением
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// Развёртывающийся блок со свойствами
class _PropsExpansionTile extends StatelessWidget {
  const _PropsExpansionTile({required this.props});

  final Map<String, Prop> props;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: const Text(
          'Характеристики',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        shape: const Border(),
        children: [
          const Divider(height: 1),
          ...props.entries.map(
                (entry) => Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.value.name,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      entry.value.value,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
