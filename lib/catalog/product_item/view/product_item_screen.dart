import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/common/menu/menu_screen.dart';
import 'package:offlinesvet/common/animated_search_bar.dart';
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
  ProductStores? _stores;
  bool _storesLoading = false;
  bool _storesRequested = false; // чтобы не грузить повторно при каждом didChangeDependencies
  List<String> _images = [];
  final _imagePageController = PageController();
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
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

  Future<void> _loadStores(String productId) async {
    setState(() => _storesLoading = true);
    final stores = await _productsRepository.getProductStores(productId);
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _storesLoading = false;
    });
  }

  Future<void> _loadImages(String productId) async {
    final images = await _productsRepository.getProductImages(productId);
    if (!mounted || images.isEmpty) return;
    setState(() => _images = images);
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
        // Пока не подгрузился полный список — показываем то, что уже
        // есть (превью), чтобы слайдер не был пустым.
        if (_images.isEmpty && args.image != null && args.image!.isNotEmpty) {
          _images = [args.image!];
        }
      });
      if (!_storesRequested) {
        _storesRequested = true;
        _loadStores(args.id);
        _loadImages(args.id);
      }
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
          const CatalogSearchBar(),
          IconButton(
            icon: SvgPicture.asset('assets/icons/menu.svg',
                width: 24, height: 24,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
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
                icon: SvgPicture.asset('assets/icons/shopping-cart.svg',
                    width: 20, height: 20,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
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

          // Картинки товара — слайдер, если их несколько
          if (_images.isNotEmpty) ...[
            SizedBox(
              height: 260,
              child: PageView.builder(
                controller: _imagePageController,
                itemCount: _images.length,
                onPageChanged: (i) => setState(() => _currentImageIndex = i),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: _images[i],
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
              ),
            ),
            if (_images.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_images.length, (i) {
                  final selected = i == _currentImageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: selected ? 10 : 8,
                    height: selected ? 10 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? const Color(0xFF4CAF50) : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
            ],
          ],

          const SizedBox(height: 20),

          // Основная информация
          _InfoRow(label: 'Артикул', value: product!.article ?? '—'),
          if (product!.brend != null) _InfoRow(label: 'Бренд', value: product!.brend!),
          if (_categoryName() != null) _InfoRow(label: 'Категория', value: _categoryName()!),

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
                        style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    Text(
                      _fmtPrice(price.price),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Наличие на складах
          if (_storesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_stores != null && (_stores!.stores.isNotEmpty || _stores!.moscowNote != null)) ...[
            Text(
              'Наличие на складах',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._stores!.stores.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(s.name, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    ),
                    Text('${s.amount}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ],
                ),
              ),
            ),
            if (_stores!.moscowNote != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_stores!.moscowNote!,
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 13)),
              ),
            const SizedBox(height: 12),
          ],

          // Свойства товара — развёртывающийся блок
          if (_detailProps(product!.props).isNotEmpty)
            _PropsExpansionTile(props: _detailProps(product!.props)),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // Ищет название раздела по ID товара в дереве _sections (разделы бывают
  // вложенными, поэтому обход рекурсивный). null, если разделы ещё не
  // загрузились или раздел не нашёлся.
  String? _categoryName() {
    final sections = _sections;
    if (sections == null || product == null) return null;
    Section? find(List<Section> list) {
      for (final s in list) {
        if (s.id == product!.sectionId) return s;
        final found = find(s.children);
        if (found != null) return found;
      }
      return null;
    }
    return find(sections)?.name;
  }

  // Allow-list: показываем на детальной карточке ТОЛЬКО эти свойства
  // (список задан явно, с нуля — как и allowCodes в get_filters.php, но
  // это отдельный, более широкий список: сюда входят и те свойства,
  // которых нет в фильтре, но которые нужны именно на карточке).
  static const _detailAllowedCodes = {
    // Только на карточке (не в фильтре)
    'STIL','KOLLEKTSIYA_BRENDA','SERIYA_KOLLEKTSII','SERIYA',
    'VYSOTA_UPAKOVKI_SM','SHIRINA_UPAKOVKI_SM','DLINA_UPAKOVKI_SM','GARANTIYA',
    '_DIAPAZON_RABOCHIKH_TEMPERATUR_S','INSTRUKCIA','kolichestvo_klavish',
    'KOLICHESTVO_POSTOV','KOMPLEKTATSIYA','LAMPY_V_KOMPLEKTE',
    'MONTAZHNOE_OTVERSTIE_SHIRINA','MONTAZHNOE_OTVERSTIE_DLINA',
    'MONTAZHNOE_OTVERSTIE_DIAMETR','MONTAZHNOE_OTVERSTIE_GLUBINA',
    'NAPRYAZHENIE_V','SVETOVOY_POTOK_LM','TIP_LAMPOCHKI_OSNOVNOY',
    // И в фильтре, и на карточке (те же, что allowCodes в get_filters.php)
    'BREND','STRANA','PLOSHCHAD_OSVESHCHENIYA_M2','INTERER',
    'VISOTA_POTOLKOV_V_POMESHENII','PODKHODIT_DLYA_NIZKIKH_POTOLKOV','NOVINKA',
    'STIL_OSVESHCHENIYA','NALICHIE_DATCHIKA_DVIZHENIYA','OBLAKO_METOK',
    'MATERIAL_PLAFONOV','MATERIAL_ARMATURY','TSVET_PLAFONOV','TSVET_ARMATURY',
    'DIAMETR_MM','DLINA_SHNURA_M','DLINA_MM','GLUBINA_MM','SHIRINA_MM','VYSOTA_MM',
    'VYSOTA_VSTRAIVAEMOY_CHASTI_MM','DIAMETR_VREZNOGO_OTVERSTIYA_MM',
    'MOSHCHNOST_1_LAMPY_W','OBSHCHAYA_MOSHCHNOST_SVETILNIKA_W','STATUS',
    'TIP_TSOKOLYA','VKHODNOE_NAPRYAZHENIE_V','NALICHIE_DIMMERA','KOLICHESTVO_LAMP',
    '_PODKHODIT_DLYA_NATYAZHNYKH_POTOLKOV','TIP_TOVARA','OBSHCHAYA_MOSHCHNOST_W',
    'MOSHCHNOST_LAMPY_W','TIP_KREPLENIYA','TSVETOVAYA_TEMPERATURA_K',
    '_DLINA_TSEPI_MM','STEPEN_ZASHCHITY_IP',
  };

  Map<String, Prop> _detailProps(Map<String, Prop> props) {
    final filtered = Map<String, Prop>.from(props)
      ..removeWhere((code, _) => !_detailAllowedCodes.contains(code));
    return filtered;
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
