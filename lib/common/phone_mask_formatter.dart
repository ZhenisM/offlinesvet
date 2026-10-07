import 'package:flutter/services.dart';

/// Маска казахстанского номера «+7 (XXX) XXX-XX-XX» — как на сайте
/// (+7 (999) 999-99-99). Без сторонних пакетов.
///
/// «+7» — код страны: при вводе его повторно набирать не нужно. Вставленный
/// номер из 11 цифр, начинающийся с 8 или 7 (87071234567 / 77071234567),
/// приводится к тому же виду. Местные номера, начинающиеся с 7 (707, 747…),
/// не обрезаются — код страны отделяется по префиксу «+7», а не по цифре.
class KzPhoneMaskFormatter extends TextInputFormatter {
  /// Цифры номера без кода страны (до 10).
  static String nationalDigits(String text) {
    final t = text.trim();
    String digits;
    if (t.startsWith('+7')) {
      digits = t.substring(2).replaceAll(RegExp(r'\D'), '');
    } else {
      digits = t.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 11 && (digits.startsWith('8') || digits.startsWith('7'))) {
        digits = digits.substring(1);
      }
    }
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  /// true — номер введён полностью (10 цифр после +7).
  static bool isComplete(String text) => nationalDigits(text).length == 10;

  static String format(String digits) {
    if (digits.isEmpty) return '';
    final b = StringBuffer('+7 (');
    for (var i = 0; i < digits.length; i++) {
      if (i == 3) b.write(') ');
      if (i == 6 || i == 8) b.write('-');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = nationalDigits(newValue.text);
    // Стёрли разделитель («-», «)», пробел) — стираем и цифру перед ним,
    // иначе маска вернёт разделитель и Backspace «залипнет».
    if (newValue.text.length < oldValue.text.length &&
        digits == nationalDigits(oldValue.text) &&
        digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final text = format(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
