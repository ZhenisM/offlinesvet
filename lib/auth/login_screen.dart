import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart' as dio_pkg;



class LoginScreen  extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen > {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> loginUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dioClient = dio_pkg.Dio();
      final dioResponse = await dioClient.post(
        'https://prons.kz/ajax/login.php',
        data: dio_pkg.FormData.fromMap({
          'login'   : _loginController.text,
          'password': _passwordController.text,
        }),
        options: dio_pkg.Options(
          responseType: dio_pkg.ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      // Совместимость с остальным кодом
      final response = _DioResponseWrapper(dioResponse);

      if (response.statusCode == 200) {
        if (response.body.isNotEmpty) {
          final data = json.decode(response.body);

          if (data["result"] != null) {
            String token = data["result"]["token"];
            String? userId = data["result"]["user_id"]?.toString();
            String? fullName = data["result"]["full_name"]?.toString();

            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString("auth_token", token);
            // Сохраняем логин и пароль для авторизации в Bitrix-админке (редактор заказов)
            await prefs.setString("bitrix_login", _loginController.text.trim());
            await prefs.setString("bitrix_password", _passwordController.text);
            if (userId != null) {
              await prefs.setString("user_id", userId);
            }
            if (fullName != null && fullName.isNotEmpty) {
              await prefs.setString("user_name", fullName);
            }

            // Сохраняем куки из dio response (dio корректно парсит Set-Cookie)
            final cookieParts = <String>[];
            final rawHeaders = dioResponse.headers.map['set-cookie'] ?? [];
            cookieParts.addAll(rawHeaders);
            if (cookieParts.isNotEmpty) {
              await prefs.setString('session_cookies', cookieParts.join(', '));
            }

            if (mounted) Navigator.pushReplacementNamed(context, "/home");
          } else {
            setState(() {
              _errorMessage = data["error_description"] ?? "Ошибка авторизации";
            });
          }
        } else {
          setState(() => _errorMessage = "Пустой ответ сервера");
        }
      } else {
        setState(() => _errorMessage = "Ошибка сервера: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Авторизация")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _loginController,
              decoration: InputDecoration(labelText: "Логин"),
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: "Пароль"),
              obscureText: true,
            ),
            SizedBox(height: 20),
            if (_errorMessage != null)
              Text(_errorMessage!, style: TextStyle(color: Colors.red)),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
              onPressed: loginUser,
              child: Text("Войти"),
            ),
          ],
        ),
      ),
    );
  }
}

/// Обёртка для совместимости dio ответа с кодом который ожидает http.Response
class _DioResponseWrapper {
  final dio_pkg.Response _r;
  _DioResponseWrapper(this._r);
  int get statusCode => _r.statusCode ?? 0;
  String get body => _r.data?.toString() ?? '';
}
