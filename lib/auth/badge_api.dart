import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ошибка входа по бейджу с текстом для менеджера.
class BadgeException implements Exception {
  BadgeException(this.message, {this.code});
  final String message;
  final String? code; // DEVICE_NOT_REGISTERED, REVOKED, …
  @override
  String toString() => message;
}

class BadgeDevice {
  const BadgeDevice({required this.registered, this.name});
  final bool registered;
  final String? name;
}

/// Результат входа по бейджу — в том же виде, что login.php.
class BadgeLoginResult {
  BadgeLoginResult({required this.token, this.userId, this.fullName, this.cookies = const []});
  final String token;
  final String? userId;
  final String? fullName;
  final List<String> cookies; // Set-Cookie сессии prons.kz для встроенного браузера
}

/// Вход по QR-бейджу на зарегистрированных планшетах шоурума.
/// Сервер: https://prons.kz/ajax/offlinesvet/badge/auth.php
class BadgeApi {
  static const _url = 'https://prons.kz/ajax/offlinesvet/badge/auth.php';
  static const _deviceKey = 'device_id';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// Номер этого устройства: создаётся один раз и не удаляется при выходе
  /// из аккаунта. По нему сервер узнаёт зарегистрированный планшет.
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey);
    if (id == null || id.length < 32) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  /// Текст из QR похож на наш бейдж.
  static bool looksLikeBadge(String? raw) =>
      raw != null && raw.trim().toUpperCase().startsWith('OSVB:');

  Future<(Map<String, dynamic>, List<String>)> _post(Map<String, dynamic> data) async {
    data['device_id'] = await deviceId();
    final Response<String> r;
    try {
      r = await _dio.post<String>(
        _url,
        data: FormData.fromMap(data),
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
      );
    } on DioException {
      throw BadgeException('Нет связи с сервером. Проверьте интернет и попробуйте ещё раз.');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(r.data ?? '') as Map<String, dynamic>;
    } catch (_) {
      throw BadgeException('Сервер ответил с ошибкой (код ${r.statusCode}).');
    }
    if (json['error'] != null) {
      throw BadgeException(json['error_description']?.toString() ?? 'Ошибка входа',
          code: json['error']?.toString());
    }
    return (json, r.headers.map['set-cookie'] ?? const <String>[]);
  }

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('auth_token') ?? '';

  BadgeDevice _device(Map<String, dynamic> j) =>
      BadgeDevice(registered: j['registered'] == true, name: j['name']?.toString());

  /// Зарегистрирован ли этот планшет (без авторизации — для экрана входа).
  Future<BadgeDevice> deviceStatus() async => _device((await _post({'action': 'device_status'})).$1);

  /// Администратор ли текущий пользователь и что с планшетом.
  Future<(bool isAdmin, BadgeDevice device)> me() async {
    final j = (await _post({'action': 'me', 'token': await _token()})).$1;
    return (j['is_admin'] == true, _device((j['device'] as Map?)?.cast<String, dynamic>() ?? const {}));
  }

  Future<BadgeDevice> registerDevice(String name) async =>
      _device((await _post({'action': 'device_register', 'token': await _token(), 'name': name})).$1);

  Future<BadgeDevice> unregisterDevice() async =>
      _device((await _post({'action': 'device_unregister', 'token': await _token()})).$1);

  Future<BadgeLoginResult> login(String qrText) async {
    final (j, cookies) = await _post({'action': 'badge_login', 'code': qrText.trim()});
    final res = (j['result'] as Map).cast<String, dynamic>();
    return BadgeLoginResult(
      token: res['token'].toString(),
      userId: res['user_id']?.toString(),
      fullName: res['full_name']?.toString(),
      cookies: cookies,
    );
  }
}
