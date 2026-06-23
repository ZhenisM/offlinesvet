import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/catalog/product_list/widgets/product_tile.dart';
import 'package:offlinesvet/common/menu/menu_screen.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

class CategoryScreen extends StatefulWidget {
  final Section section;
  final List<Product> allProducts;
  final List<Section> allSections;

  const CategoryScreen({
    super.key,
    required this.section,
    required this.allProducts,
    required this.allSections,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _repository = ProductsRepository(dio: Dio());
  final _scrollController = ScrollController();

  final List<Product> _products = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  static const int _limit = 50;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
    if (_loading || !_hasMore) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _repository.getProducts(
        sectionId: int.parse(widget.section.id),
        page: _page,
        limit: _limit,
        section: widget.section, // передаём для офлайн-режима
      );

      if (!mounted) return;
      debugPrint('Секция ${widget.section.id} (${widget.section.name}): ${result.products.length} товаров, hasMore=${result.hasMore}');
      setState(() {
        _products.addAll(result.products);
        _hasMore = result.hasMore;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _menuOpen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          sections: widget.allSections,
          products: const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.section.name),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_outlined),
            onPressed: _menuOpen,
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Подкатегории (если есть)
          if (widget.section.children.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Подкатегории',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final child = widget.section.children[i];
                  return ListTile(
                    title: Text(child.name),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryScreen(
                          section: child,
                          allProducts: const [],
                          allSections: widget.allSections,
                        ),
                      ),
                    ),
                  );
                },
                childCount: widget.section.children.length,
              ),
            ),
            const SliverToBoxAdapter(child: Divider()),
          ],

          // Заголовок товаров
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '${_products.length}${_hasMore ? '+' : ''} товар${_productCountSuffix(_products.length)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),

          // Сетка товаров — адаптивная: 2 на мобильном, 3 на планшете
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 576 ? 3 : 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProductTile(product: _products[i]),
                childCount: _products.length,
              ),
            ),
          ),

          // Лоадер / ошибка / конец списка
          SliverToBoxAdapter(
            child: _buildFooter(),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.catalog),
    );
  }

  Widget _buildFooter() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            TextButton(onPressed: _loadProducts, child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (!_hasMore && _products.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Все товары загружены: ${_products.length}',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _productCountSuffix(int count) {
    final last = count % 10;
    final lastTwo = count % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 'ов';
    if (last == 1) return '';
    if (last >= 2 && last <= 4) return 'а';
    return 'ов';
  }

}

