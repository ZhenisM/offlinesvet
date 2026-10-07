import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlinesvet/common/phone_mask_formatter.dart';

TextEditingValue _v(String t) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

void main() {
  final f = KzPhoneMaskFormatter();
  String type(String chars) {
    var cur = _v('');
    for (final c in chars.split('')) {
      cur = f.formatEditUpdate(cur, _v(cur.text + c));
    }
    return cur.text;
  }

  test('ввод местного номера, начинающегося с 7', () {
    expect(type('7071234567'), '+7 (707) 123-45-67');
  });
  test('вставка 87071234567 и 77071234567', () {
    expect(f.formatEditUpdate(_v(''), _v('87071234567')).text, '+7 (707) 123-45-67');
    expect(f.formatEditUpdate(_v(''), _v('+7 707 123 45 67')).text, '+7 (707) 123-45-67');
  });
  test('лишние цифры обрезаются', () {
    expect(type('70712345679999'), '+7 (707) 123-45-67');
  });
  test('backspace через разделитель', () {
    final full = _v('+7 (707) 123-');
    final r = f.formatEditUpdate(full, _v('+7 (707) 123'));
    expect(r.text, '+7 (707) 12');
  });
  test('полнота', () {
    expect(KzPhoneMaskFormatter.isComplete('+7 (707) 123-45-67'), isTrue);
    expect(KzPhoneMaskFormatter.isComplete('+7 (707) 123'), isFalse);
  });
}
