import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';

/// Список свойств для отображения в сравнении.
/// Порядок важен — именно в таком порядке выводятся строки.
///
/// Для каждого свойства указан:
///  - label — заголовок строки в сравнении;
///  - code  — основной CODE свойства (как в offline-фильтрах/products_repository);
///  - names — запасные варианты человекочитаемого NAME свойства с сервера,
///            на случай если у конкретного товара/категории CODE отличается —
///            именно NAME гарантированно совпадает с тем, что показывается
///            в блоке "Характеристики" на карточке товара.
class CompareProp {
  final String label;
  final String code;
  final List<String> names;
  const CompareProp(this.label, this.code, [this.names = const []]);
}

const kCompareProps = <CompareProp>[
  CompareProp('Цена',    '__price__'),   // специальный ключ — берём из prices
  CompareProp('Бренд',   '__brend__'),   // из product.brend
  CompareProp('Артикул', '__article__'), // из product.article
  CompareProp('Страна',         'STRANA',            ['Страна']),
  CompareProp('Стиль',          'STIL',              ['Стиль']),
  CompareProp('Цвет плафонов',  'TSVET_PLAFONOV',    ['Цвет плафонов']),
  CompareProp('Цвет арматуры',  'TSVET_ARMATURY',    ['Цвет арматуры']),
  CompareProp('Материал',       'MATERIAL_PLAFONOV', ['Материал плафонов', 'Материал']),
  CompareProp('Диаметр, мм',    'DIAMETR_MM',        ['Диаметр, мм']),
  CompareProp('Высота, мм',     'VYSOTA_MM',         ['Высота, мм']),
  CompareProp('Ширина, мм',     'SHIRINA_MM',        ['Ширина, мм']),
  CompareProp('Глубина, мм',    'GLUBINA_MM',        ['Глубина, мм']),
  CompareProp('Мощность светильника, W', 'MOSHCHNOST_SVETILNIKA_W',
      ['Мощность светильника, W', 'Мощность, W']),
  CompareProp('Кол-во ламп',    'KOLICHESTVO_LAMP',  ['Количество ламп', 'Кол-во ламп']),
  CompareProp('Тип цоколя',     'TIP_TSOKOLYA',      ['Тип цоколя']),
  CompareProp('Световой поток', 'SVETOVOY_POTOK',
      ['Световой поток', 'Световой поток, Лм', 'Световой поток, лм']),
];

/// Глобальное состояние сравнения
class CompareState {
  CompareState._();
  static final CompareState instance = CompareState._();

  final Set<int> _ids = {};

  bool isCompared(int productId) => _ids.contains(productId);

  void _setIds(List<int> ids) {
    _ids..clear()..addAll(ids);
    _notifyListeners();
  }

  void _toggle(int productId, bool inCompare) {
    if (inCompare) { _ids.add(productId); } else { _ids.remove(productId); }
    _notifyListeners();
  }

  final List<void Function()> _listeners = [];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _notifyListeners() { for (final l in _listeners) l(); }
}

/// Локальное хранилище сравнения на sqflite
class CompareStore {
  static CompareStore? _instance;
  static Database? _db;

  CompareStore._();
  static CompareStore get instance => _instance ??= CompareStore._();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'compare.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, _) {
      db.execute('''
        CREATE TABLE compare_items (
          product_id INTEGER PRIMARY KEY,
          product_json TEXT NOT NULL,
          added_at INTEGER NOT NULL
        )
      ''');
    });
    return _db!;
  }

  Future<void> init() async {
    final items = await getAll();
    CompareState.instance._setIds(items.map((p) => int.tryParse(p.id) ?? 0).toList());
  }

  Future<void> toggle(Product product) async {
    final productId = int.tryParse(product.id) ?? 0;
    final db = await _database;
    final exists = (await db.query('compare_items',
        where: 'product_id = ?', whereArgs: [productId], limit: 1)).isNotEmpty;

    if (exists) {
      await db.delete('compare_items', where: 'product_id = ?', whereArgs: [productId]);
      CompareState.instance._toggle(productId, false);
    } else {
      await db.insert('compare_items', {
        'product_id'   : productId,
        'product_json' : jsonEncode(_productToJson(product)),
        'added_at'     : DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      CompareState.instance._toggle(productId, true);
    }
  }

  Future<List<Product>> getAll() async {
    final db = await _database;
    final rows = await db.query('compare_items', orderBy: 'added_at ASC');
    return rows.map((r) {
      final json = jsonDecode(r['product_json'] as String) as Map<String, dynamic>;
      return Product.fromJson(json);
    }).toList();
  }

  Future<void> remove(int productId) async {
    final db = await _database;
    await db.delete('compare_items', where: 'product_id = ?', whereArgs: [productId]);
    CompareState.instance._toggle(productId, false);
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('compare_items');
    CompareState.instance._setIds([]);
  }

  /// Получить значение свойства для отображения в сравнении
  static String getPropValue(Product p, CompareProp prop) {
    switch (prop.code) {
      case '__price__':
        if (p.prices.isEmpty) return '—';
        final price = p.prices.map((x) => x.price).reduce((a, b) => a < b ? a : b);
        final formatted = price.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
        return '$formatted ₸';
      case '__brend__':
        return p.brend?.isNotEmpty == true ? p.brend! : '—';
      case '__article__':
        return p.article?.isNotEmpty == true ? p.article! : '—';
      default:
        // 1) Прямое совпадение по CODE свойства.
        final direct = p.props[prop.code];
        if (direct != null && direct.value.trim().isNotEmpty) return direct.value;

        // 2) Запасной вариант — ищем среди всех свойств товара по его
        // человекочитаемому названию (NAME с сервера). Это то же самое
        // название, что показывается в блоке "Характеристики" на карточке
        // товара, поэтому оно надёжнее CODE, который может отличаться
        // у разных категорий/товаров.
        for (final name in prop.names) {
          final normalized = name.trim().toLowerCase();
          for (final value in p.props.values) {
            if (value.name.trim().toLowerCase() == normalized &&
                value.value.trim().isNotEmpty) {
              return value.value;
            }
          }
        }
        return '—';
    }
  }

  static Map<String, dynamic> _productToJson(Product p) => {
    'id'        : p.id,
    'name'      : p.name,
    'brend'     : p.brend,
    'article'   : p.article,
    'sectionId' : p.sectionId,
    'image'     : p.image,
    'prices'    : p.prices.map((pr) => {
      'type_id'  : pr.typeId,
      'type_name': pr.typeName,
      'price'    : pr.price,
      'currency' : pr.currency,
    }).toList(),
    'props'     : p.props.map((k, v) => MapEntry(k, {
      'NAME' : v.name,
      'CODE' : v.code,
      'VALUE': v.value,
    })),
  };
}
