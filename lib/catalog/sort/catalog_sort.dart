import 'package:offlinesvet/repositories/products/models/product.dart';

/// Сортировки каталога — как панель сортировки сайта (sort.panel_osvet).
/// [code] уходит на сервер (catalog_sort.php). У «По умолчанию» нет
/// направления: сначала Maytoni/Freya с остатками, затем остальные с
/// остатками, затем только Москва, в конце — без остатков.
enum CatalogSort {
  byDefault('default', 'Сортировка', hasDirection: false),
  popular('popular', 'По популярности'),
  newest('new', 'По новизне'),
  stock('stock', 'Остатки'),
  provider('provider', 'Остаток поставщика'),
  novinka('novinka', 'Новинка'),
  price('price', 'Цена');

  const CatalogSort(this.code, this.label, {this.hasDirection = true});
  final String code;
  final String label;
  final bool hasDirection;

  /// Название в списке выбора (у «по умолчанию» — понятнее, чем «Сортировка»).
  String get optionLabel => this == CatalogSort.byDefault ? 'По умолчанию' : label;
}

const _topBrands = {'maytoni', 'freya'};

int _rank(Product p) {
  if ((p.stock ?? 0) > 0) return _topBrands.contains((p.brend ?? '').trim().toLowerCase()) ? 0 : 1;
  if ((p.stockMoscow ?? 0) > 0) return 2;
  return 3;
}

/// Базовая цена; 0 и отсутствие цены — null (такие товары в конце списка).
double? _basePrice(Product p) {
  double? v;
  for (final pr in p.prices) {
    if (pr.typeId == '1') { v = pr.price; break; }
  }
  v ??= p.prices.isNotEmpty ? p.prices.first.price : null;
  return (v == null || v <= 0) ? null : v;
}

/// Та же сортировка, что на сервере, — для офлайн-режима (товары из кэша).
/// Просмотров и «остатка поставщика» в кэше нет — для них офлайн
/// используется порядок «по умолчанию».
List<Product> sortProductsOffline(List<Product> list, CatalogSort sort, {required bool desc}) {
  final dir = desc ? -1 : 1;
  int idCmp(Product a, Product b) => (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0);
  int byDefault(Product a, Product b) {
    final c = _rank(a).compareTo(_rank(b));
    if (c != 0) return c;
    final sa = (a.stock ?? 0) + (a.stockMoscow ?? 0), sb = (b.stock ?? 0) + (b.stockMoscow ?? 0);
    return sb.compareTo(sa);
  }

  final out = List<Product>.of(list);
  out.sort((a, b) {
    int c;
    switch (sort) {
      case CatalogSort.newest:
        c = dir * idCmp(a, b);
        break;
      case CatalogSort.stock:
        c = dir * (a.stock ?? 0).compareTo(b.stock ?? 0);
        break;
      case CatalogSort.novinka:
        final na = (a.props['NOVINKA']?.value ?? '').isNotEmpty ? 1 : 0;
        final nb = (b.props['NOVINKA']?.value ?? '').isNotEmpty ? 1 : 0;
        c = dir * na.compareTo(nb);
        break;
      case CatalogSort.price:
        final pa = _basePrice(a), pb = _basePrice(b);
        if (pa == null || pb == null) {
          c = (pa == null ? 1 : 0).compareTo(pb == null ? 1 : 0);
        } else {
          c = dir * pa.compareTo(pb);
        }
        break;
      default:
        c = byDefault(a, b);
    }
    if (c == 0 && sort != CatalogSort.byDefault) c = byDefault(a, b);
    return c != 0 ? c : idCmp(a, b);
  });
  return out;
}
