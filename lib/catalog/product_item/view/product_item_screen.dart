import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/common/menu/menu_screen.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/cart/view/add_to_cart_sheet.dart';

class ProductItemScreen extends StatefulWidget {
  const ProductItemScreen({super.key});

  @override
  State<ProductItemScreen> createState() => _ProductItemScreenState();
}

class _ProductItemScreenState extends State<ProductItemScreen> {
  Product? product;
  final _productsRepository = ProductsRepository(dio: Dio());
  List<Section>? _sections;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final sections = await _productsRepository.getSections();
      if (!mounted) return;
      setState(() => _sections = sections);
    } catch (_) {
      // молча — меню покажет только "На главную"
    }
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

  String _formatPriceName(String name) {
    const map = {
      'rozn': 'Розничная',
      'opt': 'Оптовая',
      'vip': 'VIP',
      'dealer': 'Дилерская',
    };
    return map[name.toLowerCase()] ?? name;
  }

  String _fmtPrice(double price) {
    final s = price.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₸';
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
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_outlined),
            onPressed: _menuOpen,
          ),
        ],
      ),

      // Кнопка "В корзину" сверху, под ней панель навигации (2 иконки).
      // Кнопка визуально слита с панелью — фон/закругление/тень несёт
      // только AppBottomNavBar снизу, чтобы не было видимой границы.
      bottomNavigationBar: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FilledButton.icon(
                onPressed: () => showAddToCartSheet(context, product!),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('В корзину'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const AppBottomNavBar(currentTab: AppBottomTab.catalog),
          ],
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
              child: CachedNetworkImage(
                imageUrl: product!.image!,
                height: 260,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: Colors.grey,
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
                    Text(_formatPriceName(price.typeName),
                        style: const TextStyle(color: Colors.grey)),
                    Text(
                      _fmtPrice(price.price),
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
