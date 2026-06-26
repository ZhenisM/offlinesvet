import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'offline_queue.dart';
import 'sync_status_notifier.dart';

/// Сервис синхронизации.
/// Слушает connectivity, при появлении сети выполняет очередь по порядку.
class SyncService {
  static final instance = SyncService._();
  SyncService._();

  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';

  final _dio = Dio();
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  /// Запустить сервис (вызвать один раз в main() или после логина)
  void start() {
    // Обновляем счётчик при старте
    SyncStatusNotifier.instance.refresh();

    // Слушаем изменения сети
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final hasNet = result.any((r) => r != ConnectivityResult.none);
      if (hasNet) {
        debugPrint('SyncService: сеть появилась — запускаем синхронизацию');
        syncNow();
      }
    });

    // Пробуем синхронизировать сразу при старте (может уже есть сеть)
    syncNow();
  }

  void stop() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Выполнить всю очередь немедленно
  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final actions = await OfflineQueue.getAll();
      if (actions.isEmpty) return;

      debugPrint('SyncService: синхронизируем ${actions.length} действий');

      for (final action in actions) {
        final success = await _execute(action);
        if (success) {
          await OfflineQueue.remove(action.id!);
        } else {
          await OfflineQueue.incrementAttempts(action.id!);
          // Если > 5 попыток — удаляем чтобы не блокировать очередь
          if ((action.attempts + 1) >= 5) {
            debugPrint('SyncService: удаляем зависшее действие ${action.id}');
            await OfflineQueue.remove(action.id!);
          }
          // Прерываем — порядок важен, следующие могут зависеть от этого
          break;
        }
      }
    } finally {
      _isSyncing = false;
      await SyncStatusNotifier.instance.refresh();
    }
  }

  Future<bool> _execute(QueueAction action) async {
    try {
      switch (action.type) {
        case QueueActionType.createCart:
          return await _createCart(action.payload);
        case QueueActionType.updateProducts:
          return await _updateProducts(action.payload);
        case QueueActionType.setCurrent:
          return await _setCurrent(action.payload);
        case QueueActionType.setStatus:
          return await _setStatus(action.payload);
        case QueueActionType.createOrder:
          return await _createOrder(action.payload);
      }
    } catch (e) {
      debugPrint('SyncService: ошибка выполнения ${action.type.name}: $e');
      return false;
    }
  }

  Future<bool> _createCart(Map<String, dynamic> p) async {
    final r = await _dio.post(
      '$_baseUrl/cart_save.php',
      data: {...p, 'action': 'create'},
      options: Options(contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain),
    );
    return (r.statusCode ?? 0) == 200;
  }

  Future<bool> _updateProducts(Map<String, dynamic> p) async {
    final r = await _dio.post(
      '$_baseUrl/cart_save.php',
      data: {...p, 'action': 'update_products'},
      options: Options(contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain),
    );
    return (r.statusCode ?? 0) == 200;
  }

  Future<bool> _setCurrent(Map<String, dynamic> p) async {
    final r = await _dio.post(
      '$_baseUrl/cart_save.php',
      data: {...p, 'action': 'set_current'},
      options: Options(contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain),
    );
    return (r.statusCode ?? 0) == 200;
  }

  Future<bool> _setStatus(Map<String, dynamic> p) async {
    final r = await _dio.post(
      '$_baseUrl/cart_save.php',
      data: {...p, 'action': 'set_status'},
      options: Options(contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain),
    );
    return (r.statusCode ?? 0) == 200;
  }

  Future<bool> _createOrder(Map<String, dynamic> p) async {
    final r = await _dio.post(
      '$_baseUrl/create_order.php',
      data: p,
      options: Options(contentType: 'application/json',
          responseType: ResponseType.plain),
    );
    return (r.statusCode ?? 0) == 200;
  }
}
