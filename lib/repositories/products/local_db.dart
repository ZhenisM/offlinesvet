import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';
import 'package:offlinesvet/repositories/products/models/section.dart';

class LocalDb {
  static Database? _db;

  // Инициализация БД — вызывать один раз в main()
  static Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offlinesvet.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parent_id TEXT,
            children_json TEXT NOT NULL,
            saved_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brend TEXT,
            article TEXT,
            section_id TEXT NOT NULL,
            image TEXT,
            prices_json TEXT NOT NULL,
            props_json TEXT NOT NULL,
            saved_at INTEGER NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_products_section ON products(section_id)',
        );
      },
    );

    debugPrint('LocalDb: инициализирована');
  }

  static Database get _database {
    if (_db == null) throw StateError('LocalDb не инициализирован. Вызови LocalDb.init()');
    return _db!;
  }

  // -------------------------------------------------------
  // Секции
  // -------------------------------------------------------

  static Future<void> saveSections(List<Section> sections) async {
    final batch = _database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    void insertSection(Section s) {
      batch.insert(
        'sections',
        {
          'id': s.id,
          'name': s.name,
          'parent_id': s.parentId,
          'children_json': jsonEncode(s.children.map(_sectionToMap).toList()),
          'saved_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Рекурсивно сохраняем дочерние
      for (final child in s.children) {
        insertSection(child);
      }
    }

    for (final s in sections) {
      insertSection(s);
    }

    await batch.commit(noResult: true);
    debugPrint('LocalDb: сохранено ${sections.length} корневых разделов');
  }

  static Future<List<Section>> loadSections() async {
    final rows = await _database.query('sections');
    if (rows.isEmpty) return [];

    // Строим карту всех секций
    final map = <String, Section>{};
    for (final row in rows) {
      map[row['id'] as String] = Section(
        id: row['id'] as String,
        name: row['name'] as String,
        parentId: row['parent_id'] as String?,
        children: [], // заполним ниже
      );
    }

    // Строим дерево
    final roots = <Section>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final parentId = row['parent_id'] as String?;
      final section = map[id]!;

      if (parentId == null || parentId.isEmpty || !map.containsKey(parentId)) {
        roots.add(section);
      } else {
        (map[parentId]!.children as List).add(section);
      }
    }

    debugPrint('LocalDb: загружено ${roots.length} корневых разделов из кэша');
    return roots;
  }

  static Future<bool> hasSections() async {
    final result = await _database.rawQuery('SELECT COUNT(*) as cnt FROM sections');
    return (result.first['cnt'] as int) > 0;
  }

  // -------------------------------------------------------
  // Товары
  // -------------------------------------------------------

  static Future<void> saveProducts(List<Product> products) async {
    final batch = _database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final p in products) {
      batch.insert(
        'products',
        {
          'id': p.id,
          'name': p.name,
          'brend': p.brend,
          'article': p.article,
          'section_id': p.sectionId,
          'image': p.image,
          'prices_json': jsonEncode(p.prices.map((price) => {
            'type_id': price.typeId,
            'type_name': price.typeName,
            'price': price.price,
            'currency': price.currency,
          }).toList()),
          'props_json': jsonEncode(p.props.map((code, prop) => MapEntry(code, {
            'NAME': prop.name,
            'CODE': prop.code,
            'VALUE': prop.value,
          }))),
          'saved_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  static Future<List<Product>> loadProductsBySection(String sectionId) async {
    final rows = await _database.query(
      'products',
      where: 'section_id = ?',
      whereArgs: [sectionId],
    );
    return rows.map(_productFromRow).toList();
  }

  static Future<int> countProducts() async {
    final result = await _database.rawQuery('SELECT COUNT(*) as cnt FROM products');
    return result.first['cnt'] as int;
  }

  // -------------------------------------------------------
  // Конвертация
  // -------------------------------------------------------

  static Map<String, dynamic> _sectionToMap(Section s) => {
    'ID': s.id,
    'NAME': s.name,
    'PARENT_ID': s.parentId,
    'CHILDREN': s.children.map(_sectionToMap).toList(),
  };

  static Product _productFromRow(Map<String, dynamic> row) {
    final pricesList = (jsonDecode(row['prices_json'] as String) as List<dynamic>)
        .map((e) => Price.fromJson(e as Map<String, dynamic>))
        .toList();

    final propsMap = <String, Prop>{};
    (jsonDecode(row['props_json'] as String) as Map<String, dynamic>)
        .forEach((code, value) {
      if (value is Map<String, dynamic>) {
        propsMap[code] = Prop.fromJson(value);
      }
    });

    return Product(
      id: row['id'] as String,
      name: row['name'] as String,
      brend: row['brend'] as String?,
      article: row['article'] as String?,
      sectionId: row['section_id'] as String,
      image: row['image'] as String?,
      prices: pricesList,
      props: propsMap,
    );
  }
}
