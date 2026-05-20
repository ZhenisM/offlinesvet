import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/catalog/product_list/widgets/product_tile.dart';
import 'package:offlinesvet/common/menu/menu_screen.dart';

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
      body: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _itemCount,
        itemBuilder: (context, i) => _buildItem(context, i),
      ),
    );
  }

  int get _itemCount {
    int count = 0;
    if (widget.section.children.isNotEmpty) count += widget.section.children.length + 1;
    count += 1;
    count += _products.length;
    if (_loading || _error != null || !_hasMore && _products.isNotEmpty) count += 1;
    return count;
  }

  Widget _buildItem(BuildContext context, int i) {
    int offset = 0;

    if (widget.section.children.isNotEmpty) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Подкатегории', style: Theme.of(context).textTheme.titleLarge),
        );
      }
      if (i <= widget.section.children.length) {
        final child = widget.section.children[i - 1];
        return ListTile(
          title: Text(child.name),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryScreen(
                  section: child,
                  allProducts: const [],
                  allSections: widget.allSections,
                ),
              ),
            );
          },
        );
      }
      offset = widget.section.children.length + 1;
    }

    if (i == offset) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          'Товары (${_products.length}${_hasMore ? '+' : ''})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      );
    }
    offset += 1;

    final productIndex = i - offset;
    if (productIndex < _products.length) {
      return ProductTile(product: _products[productIndex]);
    }

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
            TextButton(
              onPressed: _loadProducts,
              child: const Text('Повторить'),
            ),
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
}
