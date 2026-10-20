import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';

/// Ошибка поиска по фото с текстом, который можно показать менеджеру.
class PhotoSearchException implements Exception {
  PhotoSearchException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PhotoSearchResult {
  PhotoSearchResult({
    required this.queryId,
    required this.tookMs,
    required this.products,
    required this.scores,
  });

  final String queryId;
  final int tookMs;
  final List<Product> products;

  /// Похожесть на фото по ID товара, от 0 до 1.
  final Map<String, double> scores;
}

/// Запросы к photo_search.php на prons.kz. Фото уходит туда, а не напрямую
/// на сервер поиска: тот доступен только внутри сервера, ключ к нему
/// хранится на prons.kz и в приложение не попадает.
class PhotoSearchService {
  static const _url = 'https://prons.kz/ajax/offlinesvet/photo_search.php';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 40),
  ));

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? '';
  }

  Future<PhotoSearchResult> search(String imagePath) async {
    final form = FormData.fromMap({
      'action': 'search',
      'token': await _token(),
      'file': await MultipartFile.fromFile(imagePath, filename: 'photo.jpg'),
    });

    final Response<String> r;
    try {
      r = await _dio.post<String>(
        _url,
        data: form,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true, // ошибки разбираем сами, по тексту сервера
        ),
      );
    } on DioException {
      throw PhotoSearchException(
          'Нет связи с сервером. Проверьте интернет и попробуйте ещё раз.');
    }

    final code = r.statusCode ?? 0;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(r.data ?? '') as Map<String, dynamic>;
    } catch (_) {
      // Ответ не JSON — обычно это nginx: 413 (фото больше лимита сервера)
      // или 502/504 (сервер перегружен).
      throw PhotoSearchException(code == 413
          ? 'Фото слишком большое для сервера.'
          : 'Поиск по фото сейчас недоступен (код $code).');
    }

    if (code != 200) {
      throw PhotoSearchException(
          json['error']?.toString() ?? 'Поиск по фото сейчас недоступен (код $code).');
    }

    final products = <Product>[];
    final scores = <String, double>{};
    for (final e in (json['products'] as List<dynamic>? ?? const [])) {
      final m = e as Map<String, dynamic>;
      final p = Product.fromJson(m);
      products.add(p);
      final s = m['score'];
      if (s is num) scores[p.id] = s.toDouble();
    }

    return PhotoSearchResult(
      queryId: json['query_id']?.toString() ?? '',
      tookMs: (json['took_ms'] as num?)?.toInt() ?? 0,
      products: products,
      scores: scores,
    );
  }

  /// Отметка менеджера: yes — тот самый, variant — та же модель в другом
  /// цвете или размере, no — нужного нет. Ошибки не показываем: отметка
  /// нужна только для статистики качества поиска.
  Future<void> feedback(String queryId, String verdict) async {
    if (queryId.isEmpty) return;
    try {
      await _dio.post<String>(
        _url,
        data: FormData.fromMap({
          'action': 'feedback',
          'token': await _token(),
          'query_id': queryId,
          'verdict': verdict,
        }),
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
      );
    } catch (_) {}
  }
}
