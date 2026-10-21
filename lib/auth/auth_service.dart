import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/auth/account_session.dart';
import 'package:offlinesvet/customer/customer.dart';

class AuthService {

  static Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("auth_token");

    if (token != null) {
      // Без сети или при медленном ответе выход всё равно должен пройти:
      // на планшете менеджеры меняются за секунды.
      try {
        await http.post(
          Uri.parse("https://prons.kz/ajax/logout.php"),
          body: {"token": token},
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    // Важно: чистим клиентов ДО удаления user_id — CustomerStorage
    // использует user_id как namespace и не найдёт данные после.
    await CustomerStorage.clearAll();

    // ФИО менеджера и локальные корзины принадлежат этому аккаунту —
    // следующий менеджер не должен их видеть.
    await AccountSession.onLogout();

    await prefs.remove("auth_token");
    await prefs.remove("user_id");
  }
}