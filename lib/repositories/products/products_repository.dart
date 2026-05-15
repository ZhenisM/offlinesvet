import 'package:flutter/foundation.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:dio/dio.dart';

const String _baseUrl = 'https://prons.kz/ajax/offlinesvet';

class ProductsRepository {
  ProductsRepository({required this.dio});

  final Dio dio;

  // Загружает только дерево разделов
  Future<List<Section>> getSections() async {
    final response = await dio.get('$_baseUrl/get_sections.php');
    final data = response.data as Map<String, dynamic>;
    final sectionsJson = data['sections'] as List<dynamic>;
    return sectionsJson
        .map((e) => Section.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Загружает товары одной страницы конкретного раздела
  Future<({List<Product> products, bool hasMore})> getProducts({
    required int sectionId,
    int page = 1,
    int limit = 50,
  }) async {
    final response = await dio.get(
      '$_baseUrl/get_products.php',
      queryParameters: {
        'section_id': sectionId,
        'page': page,
        'limit': limit,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final meta = data['meta'] as Map<String, dynamic>?;
    final productsJson = data['products'] as List<dynamic>;

    final products = productsJson
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();

    debugPrint('getProducts sectionId=$sectionId page=$page: ${products.length} товаров, has_more=${meta?['has_more']}');

    return (
    products: products,
    hasMore: meta?['has_more'] == true,
    );
  }
}
