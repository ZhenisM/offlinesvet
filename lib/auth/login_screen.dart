import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/auth/account_session.dart';
import 'package:offlinesvet/auth/badge_api.dart';
import 'package:offlinesvet/auth/badge_scan_screen.dart';



class LoginScreen  extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen > {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  // Вход по QR-бейджу доступен только на планшетах, которые зарегистрировал
  // администратор. Кнопка появляется, когда сервер подтвердил регистрацию.
  bool _badgeAvailable = false;
  bool _autoScanHandled = false;

  bool get _canSubmit =>
      _loginController.text.trim().isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Кнопка "Войти" должна включаться/выключаться по мере ввода —
    // пересобираем экран при любом изменении текста в полях.
    _loginController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    try {
      final d = await BadgeApi().deviceStatus();
      if (!mounted) return;
      setState(() => _badgeAvailable = d.registered);
    } catch (_) {
      return; // нет сети — остаётся обычный вход
    }
    // «Сменить менеджера» в профиле открывает этот экран с {'scan': true}:
    // сразу показываем сканер, чтобы передача планшета заняла секунды.
    final args = ModalRoute.of(context)?.settings.arguments;
    if (_badgeAvailable && !_autoScanHandled && args is Map && args['scan'] == true) {
      _autoScanHandled = true;
      _scanBadge();
    }
  }

  Future<void> _scanBadge() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BadgeScanScreen()),
    );
    if (code == null || !mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final r = await BadgeApi().login(code);
      await _completeLogin(token: r.token, userId: r.userId, fullName: r.fullName, cookies: r.cookies);
    } on BadgeException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Общее завершение входа — и по паролю, и по бейджу.
  Future<void> _completeLogin({
    required String token,
    required String? userId,
    required String? fullName,
    required List<String> cookies,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("auth_token", token);
    if (userId != null) {
      await prefs.setString("user_id", userId);
    }
    // ФИО и корзины — от нового менеджера, а не от прошлого входа.
    await AccountSession.onLogin(userId: userId, fullName: fullName);

    // Куки сессии prons.kz (PHPSESSID, BITRIX_SM_*) — для встроенного браузера.
    if (cookies.isNotEmpty) {
      await prefs.setString('session_cookies', cookies.join(', '));
    }

    if (mounted) Navigator.pushReplacementNamed(context, "/home");
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dioClient = dio_lib.Dio(dio_lib.BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final dioResp = await dioClient.post(
        'https://prons.kz/ajax/login.php',
        data: 'login=${Uri.encodeComponent(_loginController.text)}&password=${Uri.encodeComponent(_passwordController.text)}',
        options: dio_lib.Options(
          contentType: 'application/x-www-form-urlencoded',
          responseType: dio_lib.ResponseType.plain,
        ),
      );

      if (dioResp.statusCode == 200) {
        final body = dioResp.data?.toString() ?? '';
        if (body.isNotEmpty) {
          final data = json.decode(body);

          if (data["result"] != null) {
            // login.php на prons.kz устанавливает PHPSESSID и BITRIX_SM_* —
            // собираем все Set-Cookie для встроенного браузера.
            await _completeLogin(
              token: data["result"]["token"].toString(),
              userId: data["result"]["user_id"]?.toString(),
              fullName: data["result"]["full_name"]?.toString(),
              cookies: dioResp.headers.map['set-cookie'] ?? const [],
            );
          } else {
            setState(() {
              _errorMessage = data["error_description"] ?? "Ошибка авторизации";
            });
          }
        } else {
          setState(() => _errorMessage = "Пустой ответ сервера");
        }
      } else {
        setState(() => _errorMessage = "Ошибка сервера: ${dioResp.statusCode}");
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({required String hint, Widget? suffixIcon}) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(Colors.black, 1.5),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        title: const Text("Авторизация"),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _loginController,
                decoration: _fieldDecoration(hint: "Логин"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: _fieldDecoration(
                  hint: "Пароль",
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: SvgPicture.asset(
                      _obscurePassword ? 'assets/icons/eye-crossed.svg' : 'assets/icons/eye.svg',
                      width: 20, height: 20,
                      colorFilter: ColorFilter.mode(Colors.grey.shade500, BlendMode.srcIn),
                    ),
                  ),
                ),
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _canSubmit ? loginUser : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade500,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          "Войти",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
              if (_badgeAvailable && !_isLoading) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _scanBadge,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text(
                      "Войти по бейджу",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
