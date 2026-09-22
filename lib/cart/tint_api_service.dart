import 'dart:convert';
import 'package:dio/dio.dart';

/// Один найденный цвет — из ответа tint_search.php?action=search.
class TintColor {
  final String color; // "#RRGGBB"
  final String name; // код/название цвета, например "DX 30YY 63/231"
  final String series;
  final String palette; // человекочитаемое название палитры

  const TintColor({
    required this.color,
    required this.name,
    this.series = '',
    required this.palette,
  });

  factory TintColor.fromJson(Map<String, dynamic> json) => TintColor(
        color: json['color']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        series: json['series']?.toString() ?? '',
        palette: json['palette']?.toString() ?? '',
      );
}

/// Одна палитра — из ответа tint_search.php?action=palettes.
class TintPalette {
  final String code;
  final String name;

  const TintPalette({required this.code, required this.name});

  factory TintPalette.fromJson(Map<String, dynamic> json) => TintPalette(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class TintApiException implements Exception {
  final String message;
  TintApiException(this.message);
  @override
  String toString() => message;
}

/// Сервис для tint_search.php — поиск цвета и список палитр колеровки.
/// Только чтение, ничего не пишет в корзину (сама замена позиции целиком
/// идёт через уже существующий CartApiService.updateCartItems).
class TintApiService {
  TintApiService({required this.dio});
  final Dio dio;

  static const String _baseUrl = 'https://prons.kz/ajax/centrkrasok';

  Future<List<TintPalette>> loadPalettes() async {
    try {
      final response = await dio.get(
        '$_baseUrl/tint_search.php',
        queryParameters: {'action': 'palettes'},
      );
      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw TintApiException(data['error'].toString());
      }
      final result = data['result'] as List<dynamic>? ?? [];
      return result.map((e) => TintPalette.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw TintApiException('Не удалось загрузить список палитр: ${e.message}');
    }
  }

  Future<List<TintColor>> search({required String q, String paletteCode = 'all'}) async {
    try {
      final response = await dio.get(
        '$_baseUrl/tint_search.php',
        queryParameters: {'action': 'search', 'q': q, 'paletteCode': paletteCode},
      );
      final data = _ensureMap(response.data);
      if (data['error'] != null) {
        throw TintApiException(data['error'].toString());
      }
      final result = data['result'] as List<dynamic>? ?? [];
      return result.map((e) => TintColor.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw TintApiException('Не удалось выполнить поиск цвета: ${e.message}');
    }
  }

  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    if (data is Map<String, dynamic>) return data;
    throw TintApiException('Некорректный формат ответа сервера');
  }
}
