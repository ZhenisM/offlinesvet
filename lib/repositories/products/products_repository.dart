import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/repositories/products/local_db.dart';

const String _baseUrl = 'https://prons.kz/ajax/offlinesvet';

class ProductsRepository {
  ProductsRepository({required this.dio});

  final Dio dio;

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // Собирает все ID секции и её дочерних секций рекурсивно
  List<String> _collectSectionIds(Section section) {
    final ids = <String>[section.id];
    for (final child in section.children) {
      ids.addAll(_collectSectionIds(child));
    }
    return ids;
  }

  // -------------------------------------------------------
  // Секции
  // -------------------------------------------------------
  Future<List<Section>> getSections() async {
    final online = await _hasInternet();

    if (!online) {
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
  // Товары по списку ID (для отображения в мультикорзине)
  // -------------------------------------------------------
  Future<List<Product>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    try {
      final response = await dio.get(
        '$_baseUrl/get_products_by_ids.php',
        queryParameters: {'ids': ids.join(',')},
        options: Options(responseType: ResponseType.plain),
      );

      // Явно декодируем — не доверяем автопарсингу Dio,
      // сервер может вернуть text/html Content-Type даже при JSON-теле.
      final raw = response.data as String;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final productsJson = decoded['products'] as List<dynamic>;

      debugPrint('getProductsByIds: получили ${productsJson.length} товаров');

      return productsJson
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getProductsByIds: ошибка ($e), ищем в кэше');
      try {
        final allCached = await Future.wait(
          ids.map((id) => LocalDb.loadProductsBySection(id)),
        );
        return allCached
            .expand((list) => list)
            .where((p) => ids.contains(p.id))
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  // -------------------------------------------------------
  // собрать товары из всех дочерних секций
  // -------------------------------------------------------
  Future<({List<Product> products, bool hasMore})> getProducts({
    required int sectionId,
    int page = 1,
    int limit = 50,
    Section? section, // передаём для офлайн-режима
  }) async {
    final online = await _hasInternet();

    if (!online) {
      debugPrint('getProducts: offline, читаем из кэша sectionId=$sectionId');

      List<Product> cached;
      if (section != null && section.children.isNotEmpty) {
        // Собираем товары из всех вложенных секций
        final allIds = _collectSectionIds(section);
        debugPrint('getProducts: офлайн, собираем из ${allIds.length} секций: $allIds');
        final futures = allIds.map((id) => LocalDb.loadProductsBySection(id));
        final results = await Future.wait(futures);
        cached = results.expand((list) => list).toList();
      } else {
        cached = await LocalDb.loadProductsBySection(sectionId.toString());
      }

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

      List<Product> cached;
      if (section != null && section.children.isNotEmpty) {
        final allIds = _collectSectionIds(section);
        final futures = allIds.map((id) => LocalDb.loadProductsBySection(id));
        final results = await Future.wait(futures);
        cached = results.expand((list) => list).toList();
      } else {
        cached = await LocalDb.loadProductsBySection(sectionId.toString());
      }

      return (products: cached, hasMore: false);
    }
  }
}
