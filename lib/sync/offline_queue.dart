import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Типы действий которые можно поставить в очередь
enum QueueActionType {
  createCart,
  updateProducts,
  setCurrent,
  setStatus,
  createOrder,
}

class QueueAction {
  final int? id;
  final QueueActionType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  const QueueAction({
    this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
  });

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'payload': jsonEncode(payload),
    'created_at': createdAt.toIso8601String(),
    'attempts': attempts,
  };

  factory QueueAction.fromMap(Map<String, dynamic> m) => QueueAction(
    id: m['id'] as int?,
    type: QueueActionType.values.firstWhere((e) => e.name == m['type']),
    payload: jsonDecode(m['payload'] as String) as Map<String, dynamic>,
    createdAt: DateTime.parse(m['created_at'] as String),
    attempts: (m['attempts'] as int?) ?? 0,
  );
}

/// Локальная очередь действий на основе sqflite
class OfflineQueue {
  static const _dbName = 'offline_queue.db';
  static const _table  = 'queue';
  static Database? _db;

  static Future<Database> _open() async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _dbName),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_table (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          type       TEXT NOT NULL,
          payload    TEXT NOT NULL,
          created_at TEXT NOT NULL,
          attempts   INTEGER DEFAULT 0
        )
      '''),
    );
    return _db!;
  }

  /// Добавить действие в очередь
  static Future<int> enqueue(QueueActionType type, Map<String, dynamic> payload) async {
    final db = await _open();
    return db.insert(_table, QueueAction(
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    ).toMap());
  }

  /// Получить все действия по порядку
  static Future<List<QueueAction>> getAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'id ASC');
    return rows.map(QueueAction.fromMap).toList();
  }

  /// Количество ожидающих действий
  static Future<int> count() async {
    final db = await _open();
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM $_table');
    return (result.first['c'] as int?) ?? 0;
  }

  /// Удалить выполненное действие
  static Future<void> remove(int id) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Увеличить счётчик попыток
  static Future<void> incrementAttempts(int id) async {
    final db = await _open();
    await db.execute(
      'UPDATE $_table SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  /// Очистить всю очередь (например после logout)
  static Future<void> clear() async {
    final db = await _open();
    await db.delete(_table);
  }
}
