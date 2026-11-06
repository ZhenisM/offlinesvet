import 'package:flutter/widgets.dart';

/// Число колонок в сетках товаров по ширине экрана:
/// телефон — 2, планшет вертикально — 3, планшет горизонтально — 4,
/// большой планшет горизонтально — 5.
/// (iPad mini: 744 pt → 3, 1133 pt → 4; iPad Pro 12.9": 1366 pt → 5.)
int catalogColumns(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w >= 1200) return 5;
  if (w >= 900) return 4;
  if (w >= 576) return 3;
  return 2;
}
