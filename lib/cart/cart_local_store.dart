import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:offlinesvet/cart/models/cart_model.dart';

/// Локальное зеркало корзин в sqflite.
/// При наличии сети загружает с сервера и сохраняет сюда.
/// При offline читает отсюда.
/// Количество товаров (сумма количеств) в ТЕКУЩЕЙ корзине — для красного значка на иконке
/// корзины в нижнем меню. Обновляется при любом изменении корзин в
/// локальной базе (добавление товара, смена текущей корзины, синхронизация).
class CartBadge {
  CartBadge._();
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  static Future<void> refresh() async {
    try {
      final carts = await CartLocalStore.loadAll();
      final current = carts.where((c) => c.isCurrent).toList();
      // Как «N товаров» в корзине: сумма количеств, а не число позиций.
      count.value = current.isEmpty
          ? 0
          : current.first.items.fold<double>(0, (sum, i) => sum + i.quantity).round();
    } catch (e) {
      debugPrint('CartBadge.refresh: $e');
    }
  }
}

class CartLocalStore {
  static const _dbName = 'carts_local.db';
  static const _table  = 'carts';
  static Database? _db;

  static Future<Database> _open() async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _dbName),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_table (
          id            TEXT PRIMARY KEY,
          title         TEXT NOT NULL,
          status        TEXT NOT NULL DEFAULT "в работе",
          is_current    INTEGER NOT NULL DEFAULT 0,
          date_create   TEXT NOT NULL,
          client_info   TEXT,
          products_info TEXT NOT NULL DEFAULT ""
        )
      '''),
    );
    return _db!;
  }

  /// Сохранить список корзин с сервера (полная замена)
  static Future<void> saveAll(List<Cart> carts) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_table);
      for (final cart in carts) {
        await txn.insert(_table, _toMap(cart),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    unawaited(CartBadge.refresh());
  }

  /// Загрузить все корзины из локальной БД
  static Future<List<Cart>> loadAll() async {
    final db = await _open();
    final rows = await db.query(_table,
        orderBy: 'is_current DESC, date_create DESC');
    return rows.map(_fromMap).toList();
  }

  /// Обновить товары корзины локально
  static Future<void> updateProducts(String basketId, String productsInfo) async {
    final db = await _open();
    await db.update(_table, {'products_info': productsInfo},
        where: 'id = ?', whereArgs: [basketId]);
    unawaited(CartBadge.refresh());
  }

  /// Переключить текущую корзину локально
  static Future<void> setCurrent(String basketId) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.update(_table, {'is_current': 0});
      await txn.update(_table, {'is_current': 1},
          where: 'id = ?', whereArgs: [basketId]);
    });
    unawaited(CartBadge.refresh());
  }

  /// Добавить новую корзину
  static Future<void> insertCart(Cart cart) async {
    final db = await _open();
    await db.insert(_table, _toMap(cart),
        conflictAlgorithm: ConflictAlgorithm.replace);
    unawaited(CartBadge.refresh());
  }

  /// Удалить корзину
  static Future<void> deleteCart(String basketId) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [basketId]);
    unawaited(CartBadge.refresh());
  }

  /// Заменить временный ID на реальный после синхронизации
  static Future<void> replaceId(String tempId, String realId) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [tempId]);
    if (rows.isEmpty) return;
    final data = Map<String, dynamic>.from(rows.first);
    data['id'] = realId;
    await db.transaction((txn) async {
      await txn.delete(_table, where: 'id = ?', whereArgs: [tempId]);
      await txn.insert(_table, data,
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    unawaited(CartBadge.refresh());
  }

  static Map<String, dynamic> _toMap(Cart cart) => {
    'id':           cart.id,
    'title':        cart.title,
    'status':       cart.status.label,
    'is_current':   cart.isCurrent ? 1 : 0,
    'date_create':  cart.dateCreate.toIso8601String(),
    'client_info':  cart.clientInfo != null ? jsonEncode(cart.clientInfo) : null,
    'products_info': encodeCartItems(cart.items),
  };

  static Cart _fromMap(Map<String, dynamic> m) => Cart(
    id:          m['id'] as String,
    title:       m['title'] as String,
    status:      CartStatus.fromLabel(m['status'] as String? ?? 'в работе'),
    isCurrent:   (m['is_current'] as int) == 1,
    dateCreate:  DateTime.tryParse(m['date_create'] as String? ?? '') ?? DateTime.now(),
    clientInfo:  m['client_info'] != null
        ? jsonDecode(m['client_info'] as String) as Map<String, dynamic>
        : null,
    items:       decodeCartItems(m['products_info'] as String? ?? ''),
  );
}
