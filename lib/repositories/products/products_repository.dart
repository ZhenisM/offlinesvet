import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:offlinesvet/repositories/products/products.dart';
import 'package:offlinesvet/repositories/products/local_db.dart';
import 'package:offlinesvet/catalog/filter/filter_screen.dart';

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
  // -------------------------------------------------------
  // Товары по списку ID (для отображения в мультикорзине)
  // Кэшируются в SharedPreferences по productId — работает offline
  // -------------------------------------------------------
  static const _cacheKey = 'products_by_id_cache';

  Future<void> _cacheRawProducts(List<dynamic> rawProducts) async {
    if (rawProducts.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_cacheKey);
      final Map<String, dynamic> cache = existing != null
          ? jsonDecode(existing) as Map<String, dynamic>
          : {};
      for (final raw in rawProducts) {
        final map = raw as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) cache[id] = jsonEncode(map);
      }
      await prefs.setString(_cacheKey, jsonEncode(cache));
    } catch (e) {
      debugPrint('_cacheRawProducts: ошибка: $e');
    }
  }

  Future<List<Product>> _loadFromCache(List<String> ids) async {
    // Источник 1: узкий кэш "товары по ID" (SharedPreferences) — заполняется
    // только когда товар уже показывался именно в корзине при интернете.
    final found = <String, Product>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_cacheKey);
      if (existing != null) {
        final cache = jsonDecode(existing) as Map<String, dynamic>;
        for (final id in ids) {
          if (cache.containsKey(id)) {
            final map = jsonDecode(cache[id] as String) as Map<String, dynamic>;
            found[id] = Product.fromJson(map);
          }
        }
      }
    } catch (e) {
      debugPrint('_loadFromCache: ошибка чтения products_by_id_cache: $e');
    }

    // Источник 2: общий кэш каталога (LocalDb/sqflite) — наполняется при
    // обычном офлайн-просмотре разделов. Раньше сюда не заглядывали вообще,
    // из-за чего товары, добавленные в корзину офлайн, но ни разу не
    // показанные именно в корзине при интернете, оставались без
    // названия/цены/картинки, даже если реально лежали в кэше каталога.
    final missing = ids.where((id) => !found.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final fromCatalog = await LocalDb.loadProductsByIds(missing);
      for (final p in fromCatalog) {
        found[p.id] = p;
      }
    }

    final result = ids.where(found.containsKey).map((id) => found[id]!).toList();
    debugPrint('_loadFromCache: найдено ${result.length}/${ids.length} товаров (id-кэш + каталог)');
    return result;
  }

  Future<List<Product>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    final online = await _hasInternet();

    if (!online) {
      debugPrint('getProductsByIds: offline — читаем из кэша');
      return _loadFromCache(ids);
    }

    try {
      final response = await dio.get(
        '$_baseUrl/get_products_by_ids.php',
        queryParameters: {'ids': ids.join(',')},
        options: Options(responseType: ResponseType.plain),
      );

      final raw = response.data as String;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final productsJson = decoded['products'] as List<dynamic>;

      debugPrint('getProductsByIds: получили ${productsJson.length} товаров');

      final products = productsJson
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();

      // Кэшируем для offline (не ждём)
      _cacheRawProducts(productsJson);

      return products;
    } catch (e) {
      debugPrint('getProductsByIds: ошибка ($e), читаем из кэша');
      return _loadFromCache(ids);
    }
  }

  /// Все картинки товара (основная + доп. фото) для слайдера на детальной
  /// карточке — только онлайн, без офлайн-кэша (как и остатки по складам:
  /// это подгружается точечно, когда открыта конкретная карточка).
  Future<List<String>> getProductImages(String productId) async {
    try {
      final response = await dio.get(
        '$_baseUrl/get_product_images.php',
        queryParameters: {'product_id': productId},
        options: Options(responseType: ResponseType.plain),
      );
      final decoded = jsonDecode(response.data as String) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        debugPrint('getProductImages: ошибка сервера: ${decoded['error']}');
        return const [];
      }
      final result = decoded['result'] as Map<String, dynamic>;
      final imagesJson = result['images'] as List<dynamic>? ?? [];
      return imagesJson.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('getProductImages: ошибка ($e)');
      return const [];
    }
  }

  /// Остатки товара по складам — только онлайн (актуальность важнее
  /// офлайн-доступности для этих данных, поэтому без кэша/фолбэка: если
  /// нет сети, просто вернём пустой список и экран покажет "нет данных").
  Future<ProductStores> getProductStores(String productId) async {
    try {
      final response = await dio.get(
        '$_baseUrl/get_product_stores.php',
        queryParameters: {'product_id': productId},
        options: Options(responseType: ResponseType.plain),
      );
      final decoded = jsonDecode(response.data as String) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        debugPrint('getProductStores: ошибка сервера: ${decoded['error']}');
        return const ProductStores(stores: [], moscowNote: null);
      }
      final result = decoded['result'] as Map<String, dynamic>;
      final storesJson = result['stores'] as List<dynamic>? ?? [];
      return ProductStores(
        stores: storesJson.map((e) => StoreStock.fromJson(e as Map<String, dynamic>)).toList(),
        moscowNote: result['moscow_note'] as String?,
      );
    } catch (e) {
      debugPrint('getProductStores: ошибка ($e)');
      return const ProductStores(stores: [], moscowNote: null);
    }
  }


  // -------------------------------------------------------
  // собрать товары из всех дочерних секций
  // -------------------------------------------------------
  // ВАЖНО: раньше грузило ВСЕ товары раздела разом (Future.wait по
  // каждой подсекции без ограничения) — для маленьких разделов это было
  // незаметно, но после полной синхронизации каталога некоторые разделы
  // (например, "Люстры") содержат тысячи товаров, и такой единоразовый
  // запрос ронял приложение с OutOfMemoryError на границе Flutter/Android.
  // Теперь поддерживает limit/offset через один комбинированный SQL-запрос.
  Future<List<Product>> _loadCachedProductsForSection(
    int sectionId,
    Section? section, {
    int? limit,
    int? offset,
  }) async {
    final sectionIds = (section != null && section.children.isNotEmpty)
        ? _collectSectionIds(section)
        : [sectionId.toString()];
    debugPrint('_loadCachedProductsForSection: секции ${sectionIds.length}, limit=$limit offset=$offset');
    return LocalDb.loadProductsForSections(sectionIds, limit: limit, offset: offset);
  }

  Future<({List<Product> products, bool hasMore})> getProducts({
    required int sectionId,
    int page = 1,
    int limit = 50,
    Section? section, // передаём для офлайн-режима
  }) async {
    final online = await _hasInternet();

    if (!online) {
      debugPrint('getProducts: offline, читаем из кэша sectionId=$sectionId page=$page');
      final cached = await _loadCachedProductsForSection(
        sectionId, section,
        limit: limit, offset: (page - 1) * limit,
      );
      // Как и на сервере: если пришла полная страница — считаем, что
      // дальше может быть ещё (без лишнего COUNT(*) по всем подсекциям).
      return (products: cached, hasMore: cached.length == limit);
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
      final cached = await _loadCachedProductsForSection(
        sectionId, section,
        limit: limit, offset: (page - 1) * limit,
      );
      return (products: cached, hasMore: cached.length == limit);
    }
  }

  // -------------------------------------------------------
  // Фильтры — офлайн-замена get_filters.php / get_products_filtered.php
  // -------------------------------------------------------

  // Allow-list: те же коды, что в get_filters.php на сервере — только эти
  // свойства предлагаются как фильтр (список задан явно, с нуля).
  static const _filterAllowCodes = {
    'BREND','STRANA','PLOSHCHAD_OSVESHCHENIYA_M2','INTERER','_NALICHIYE___',
    'VISOTA_POTOLKOV_V_POMESHENII','PODKHODIT_DLYA_NIZKIKH_POTOLKOV','NOVINKA',
    'STIL_OSVESHCHENIYA','NALICHIE_DATCHIKA_DVIZHENIYA','OBLAKO_METOK',
    'MATERIAL_PLAFONOV','MATERIAL_ARMATURY','TSVET_PLAFONOV','TSVET_ARMATURY',
    'DIAMETR_MM','DLINA_SHNURA_M','DLINA_MM','GLUBINA_MM','SHIRINA_MM','VYSOTA_MM',
    'AKTSIYA','VYSOTA_VSTRAIVAEMOY_CHASTI_MM','DIAMETR_VREZNOGO_OTVERSTIYA_MM',
    'MOSHCHNOST_1_LAMPY_W','OBSHCHAYA_MOSHCHNOST_SVETILNIKA_W','STATUS',
    'TIP_TSOKOLYA','VKHODNOE_NAPRYAZHENIE_V','NALICHIE_DIMMERA','KOLICHESTVO_LAMP',
    '_PODKHODIT_DLYA_NATYAZHNYKH_POTOLKOV','TIP_TOVARA','OBSHCHAYA_MOSHCHNOST_W',
    'MOSHCHNOST_LAMPY_W','TIP_KREPLENIYA','TSVETOVAYA_TEMPERATURA_K',
    '_DLINA_TSEPI_MM','STEPEN_ZASHCHITY_IP',
  };

  // Те же коды, что в get_filters.php — свойства-"диапазоны" (мм/Вт/В/м2/шт),
  // а не списки конкретных значений.
  static const _filterRangeCodes = {
    'PLOSHCHAD_OSVESHCHENIYA_M2','VISOTA_POTOLKOV_V_POMESHENII',
    'DIAMETR_MM','DLINA_SHNURA_M','DLINA_MM','GLUBINA_MM','SHIRINA_MM','VYSOTA_MM',
    'VYSOTA_VSTRAIVAEMOY_CHASTI_MM','DIAMETR_VREZNOGO_OTVERSTIYA_MM',
    'MOSHCHNOST_1_LAMPY_W','OBSHCHAYA_MOSHCHNOST_SVETILNIKA_W',
    'VKHODNOE_NAPRYAZHENIE_V','KOLICHESTVO_LAMP','OBSHCHAYA_MOSHCHNOST_W',
    'MOSHCHNOST_LAMPY_W','TSVETOVAYA_TEMPERATURA_K','_DLINA_TSEPI_MM',
  };

  static const _filterSortPriority = {
    'BREND': 0, 'STIL': 1, 'TSVET_ARMATURY': 2, 'TSVET_PLAFONOV': 3,
  };

  /// Строит определения фильтров (диапазон цены + список вариантов по
  /// каждому свойству) из уже закэшированных офлайн товаров раздела —
  /// офлайн-замена get_filters.php. Работает только с тем, что уже есть
  /// в LocalDb (полная синхронизация каталога / просмотренные разделы).
  Future<({RangeValues priceRange, List<FilterDef> filters})> buildOfflineFilterDefs(Section section) async {
    final sectionIds = section.children.isNotEmpty
        ? _collectSectionIds(section)
        : [section.id];
    final products = await LocalDb.loadAllProductsForSectionsBatched(sectionIds);

    double priceMin = 0, priceMax = 0;
    bool priceSet = false;
    final listValues = <String, Set<String>>{};
    final listValueCounts = <String, Map<String, int>>{}; // сейчас заполняется только для "В наличии"
    final propNames = <String, String>{};
    final rangeMin = <String, double>{};
    final rangeMax = <String, double>{};

    for (final p in products) {
      for (final price in p.prices) {
        if (price.typeId != '1') continue;
        final v = price.price;
        if (v <= 0) continue;
        if (!priceSet || v < priceMin) priceMin = v;
        if (!priceSet || v > priceMax) priceMax = v;
        priceSet = true;
      }

      for (final entry in p.props.entries) {
        final code = entry.key;
        if (!_filterAllowCodes.contains(code)) continue;
        final rawValue = entry.value.value.trim();
        if (rawValue.isEmpty) continue;
        propNames.putIfAbsent(code, () => entry.value.name);

        if (_filterRangeCodes.contains(code)) {
          final n = double.tryParse(rawValue);
          if (n == null || n <= 0) continue;
          if (!rangeMin.containsKey(code) || n < rangeMin[code]!) rangeMin[code] = n;
          if (!rangeMax.containsKey(code) || n > rangeMax[code]!) rangeMax[code] = n;
        } else {
          // "В наличии" — множественное свойство (товар может лежать сразу
          // на нескольких складах), а get_products_full.php склеивает
          // несколько значений через ", " в одну строку при кэшировании.
          // Разбиваем обратно, иначе это считалось бы одним "составным"
          // вариантом фильтра вместо нескольких отдельных складов, и
          // счётчик по каждому складу был бы неверным.
          final values = code == '_NALICHIYE___'
              ? rawValue.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty)
              : [rawValue];
          for (final value in values) {
            (listValues[code] ??= <String>{}).add(value);
            if (code == '_NALICHIYE___') {
              final counts = listValueCounts[code] ??= <String, int>{};
              counts[value] = (counts[value] ?? 0) + 1;
            }
          }
        }
      }
    }

    final filters = <FilterDef>[];
    listValues.forEach((code, values) {
      if (values.isEmpty) return;
      final sorted = values.toList()..sort();
      filters.add(FilterDef(
        code: code,
        name: propNames[code] ?? code,
        type: 'list',
        values: sorted,
        valueCounts: listValueCounts[code] ?? const {},
      ));
    });
    rangeMax.forEach((code, mx) {
      final mn = rangeMin[code] ?? 0;
      if (mx <= 0 || mx < mn) return;
      filters.add(FilterDef(code: code, name: propNames[code] ?? code, type: 'range', min: mn, max: mx));
    });

    filters.sort((a, b) =>
        (_filterSortPriority[a.code] ?? 99).compareTo(_filterSortPriority[b.code] ?? 99));

    debugPrint('buildOfflineFilterDefs: ${filters.length} фильтров из ${products.length} товаров');

    return (
      priceRange: RangeValues(priceSet ? priceMin : 0, priceSet ? priceMax : 0),
      filters: filters,
    );
  }

  /// Применяет уже выбранные фильтры локально к товарам раздела — офлайн-
  /// замена get_products_filtered.php. Возвращает сразу все подходящие
  /// товары (без серверной пагинации — офлайн-датасет на раздел разумного
  /// размера, догружать постранично не требуется).
  Future<List<Product>> applyFiltersOffline(Section section, ActiveFilters filters) async {
    final sectionIds = section.children.isNotEmpty
        ? _collectSectionIds(section)
        : [section.id];
    final products = await LocalDb.loadAllProductsForSectionsBatched(sectionIds);

    return products.where((p) {
      if (filters.price != null) {
        final hasMatchingPrice = p.prices.any((price) =>
            price.typeId == '1' &&
            price.price >= filters.price!.start &&
            price.price <= filters.price!.end);
        if (!hasMatchingPrice) return false;
      }

      for (final entry in filters.ranges.entries) {
        final propValue = p.props[entry.key]?.value;
        final n = propValue == null ? null : double.tryParse(propValue);
        if (n == null || n < entry.value.start || n > entry.value.end) return false;
      }

      for (final entry in filters.props.entries) {
        if (entry.value.isEmpty) continue;
        final propValue = p.props[entry.key]?.value;
        if (propValue == null || !entry.value.contains(propValue)) return false;
      }

      return true;
    }).toList();
  }
}
