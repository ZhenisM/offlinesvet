import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/customer/customer.dart';

class AuthService {

  static Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("auth_token");

    if (token != null) {
      await http.post(
        Uri.parse("https://prons.kz/ajax/logout.php"),
        body: {"token": token},
      );
    }

    // Важно: чистим клиентов ДО удаления токена — CustomerStorage
    // использует auth_token как namespace и не найдёт данные после.
    await CustomerStorage.clearAll();

    await prefs.remove("auth_token");
  }
}