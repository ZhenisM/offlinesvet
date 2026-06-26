import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:offlinesvet/cart/cart_api_service.dart';
import 'package:offlinesvet/cart/cart_local_store.dart';
import 'package:offlinesvet/cart/models/cart_model.dart';
import 'package:offlinesvet/customer/models/customer_model.dart';
import 'package:offlinesvet/sync/offline_queue.dart';
import 'package:offlinesvet/sync/sync_service.dart';
import 'package:offlinesvet/sync/sync_status_notifier.dart';

/// Обёртка над CartApiService с поддержкой offline-режима.
/// Используйте вместо CartApiService в cart_screen.dart.
class CartApiServiceOffline {
  final CartApiService _online;

  CartApiServiceOffline({required Dio dio})
      : _online = CartApiService(dio: dio);

  static Future<bool> _hasNetwork() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  // -------------------------------------------------------
  // Загрузка корзин
  // -------------------------------------------------------
  Future<List<Cart>> loadCarts({required int managerId}) async {
    if (await _hasNetwork()) {
      try {
        final carts = await _online.loadCarts(managerId: managerId);
        await CartLocalStore.saveAll(carts);
        return carts;
      } catch (e) {
        debugPrint('CartApiOffline.loadCarts: ошибка онлайн, берём локальные: $e');
      }
    }
    debugPrint('CartApiOffline.loadCarts: offline — читаем sqflite');
    return CartLocalStore.loadAll();
  }

  // -------------------------------------------------------
  // Создание корзины
  // -------------------------------------------------------
  Future<String> createCart({
    required int managerId,
    required Customer customer,
  }) async {
    if (await _hasNetwork()) {
      final id = await _online.createCart(
          managerId: managerId, customer: customer);
      // Перезагружаем все корзины чтобы синхронизировать локальное зеркало
      try {
        final carts = await _online.loadCarts(managerId: managerId);
        await CartLocalStore.saveAll(carts);
      } catch (_) {}
      return id;
    }

    // Offline — временный ID
    final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final tempCart = Cart(
      id:          tempId,
      title:       customer.fullName,
      status:      CartStatus.inProgress,
      isCurrent:   true,
      dateCreate:  DateTime.now(),
      clientInfo:  null,
      items:       const [],
    );
    await CartLocalStore.setCurrent(tempId);
    await CartLocalStore.insertCart(tempCart);

    // В очередь синхронизации
    await OfflineQueue.enqueue(QueueActionType.createCart, {
      'manager_id':  managerId.toString(),
      'title':       customer.fullName,
      'client_info': jsonEncode(customer.toMultibasketsClientInfo()),
      '_temp_id':    tempId,
    });
    await SyncStatusNotifier.instance.refresh();

    return tempId;
  }

  // -------------------------------------------------------
  // Обновление товаров
  // -------------------------------------------------------
  Future<void> updateCartItems({
    required String basketId,
    required List<CartItem> items,
  }) async {
    final productsInfo = encodeCartItems(items);

    // Локально всегда применяем сразу
    await CartLocalStore.updateProducts(basketId, productsInfo);

    if (await _hasNetwork() && !basketId.startsWith('local_')) {
      try {
        await _online.updateCartItems(basketId: basketId, items: items);
        return;
      } catch (e) {
        debugPrint('CartApiOffline.updateCartItems: онлайн не удалось, ставим в очередь: $e');
      }
    }

    // В очередь
    await OfflineQueue.enqueue(QueueActionType.updateProducts, {
      'basket_id':     basketId,
      'products_info': productsInfo,
    });
    await SyncStatusNotifier.instance.refresh();
    SyncService.instance.syncNow();
  }

  // -------------------------------------------------------
  // Переключение текущей корзины
  // -------------------------------------------------------
  Future<void> setCurrentCart({
    required String basketId,
    required int managerId,
  }) async {
    await CartLocalStore.setCurrent(basketId);

    if (await _hasNetwork() && !basketId.startsWith('local_')) {
      try {
        await _online.setCurrentCart(basketId: basketId, managerId: managerId);
        return;
      } catch (e) {
        debugPrint('CartApiOffline.setCurrentCart: онлайн не удалось: $e');
      }
    }

    await OfflineQueue.enqueue(QueueActionType.setCurrent, {
      'basket_id':  basketId,
      'manager_id': managerId.toString(),
    });
    await SyncStatusNotifier.instance.refresh();
  }

  // -------------------------------------------------------
  // Статус корзины
  // -------------------------------------------------------
  Future<void> setCartStatus({
    required String basketId,
    required CartStatus status,
  }) async {
    await CartLocalStore.deleteCart(basketId);

    if (await _hasNetwork() && !basketId.startsWith('local_')) {
      try {
        await _online.setCartStatus(basketId: basketId, status: status);
        return;
      } catch (e) {
        debugPrint('CartApiOffline.setCartStatus: онлайн не удалось: $e');
      }
    }

    await OfflineQueue.enqueue(QueueActionType.setStatus, {
      'basket_id': basketId,
      'status':    status.label,
    });
    await SyncStatusNotifier.instance.refresh();
  }
}
