import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/repositories/products/local_db.dart';

const String _baseUrl = 'https://prons.kz/ajax/offlinesvet';

class ProductsRepository {
  ProductsRepository({required this.dio});

  final Dio dio;

  // Проверка интернета
  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // -------------------------------------------------------
  // Секции — сначала из кэша, потом обновляем с сервера
  // -------------------------------------------------------
  Future<List<Section>> getSections() async {
    final online = await _hasInternet();

    if (!online) {
      // Нет интернета — берём из локальной БД
      debugPrint('getSections: offline, читаем из кэша');
      return LocalDb.loadSections();
    }

    try {
      final response = await dio.get('$_baseUrl/get_sections.php');
      final data = response.data as Map<String, dynamic>;
      final sectionsJson = data['sections'] as List<dynamic>;
      final sections = sectionsJson
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList();

      // Сохраняем в локальную БД фоново
      LocalDb.saveSections(sections).then((_) {
        debugPrint('getSections: сохранено ${sections.length} разделов');
      });

      return sections;
    } catch (e) {
      debugPrint('getSections: ошибка сети, читаем из кэша: $e');
      return LocalDb.loadSections();
    }
  }

  // -------------------------------------------------------
  // Товары — сначала из кэша, потом обновляем с сервера
  // -------------------------------------------------------
  Future<({List<Product> products, bool hasMore})> getProducts({
    required int sectionId,
    int page = 1,
    int limit = 50,
  }) async {
    final online = await _hasInternet();

    if (!online) {
      // Нет интернета — берём из локальной БД
      debugPrint('getProducts: offline, читаем из кэша sectionId=$sectionId');
      final cached = await LocalDb.loadProductsBySection(sectionId.toString());
      return (products: cached, hasMore: false);
    }

    try {
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

      debugPrint('getProducts sectionId=$sectionId page=$page: ${products.length} товаров');

      // Сохраняем в локальную БД фоново
      if (products.isNotEmpty) {
        LocalDb.saveProducts(products).then((_) {
          debugPrint('getProducts: сохранено ${products.length} товаров в кэш');
        });
      }

      return (
      products: products,
      hasMore: meta?['has_more'] == true,
      );
    } catch (e) {
      debugPrint('getProducts: ошибка сети, читаем из кэша: $e');
      final cached = await LocalDb.loadProductsBySection(sectionId.toString());
      return (products: cached, hasMore: false);
    }
  }
}
