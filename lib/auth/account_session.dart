import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/cart/cart_api_service_offline.dart';
import 'package:offlinesvet/cart/cart_local_store.dart';

/// Данные, привязанные к вошедшему менеджеру, которые нужно сбрасывать
/// при смене аккаунта: ФИО менеджера и локальная копия корзин (по ней
/// считается красный значок корзины в нижнем меню).
class AccountSession {
  AccountSession._();

  /// Чей user_id сейчас лежит в локальной копии корзин.
  static const _cartsOwnerKey = 'carts_owner_id';

  /// Вызывать сразу после успешного входа.
  static Future<void> onLogin({required String? userId, required String? fullName}) async {
    final prefs = await SharedPreferences.getInstance();

    // ФИО — только от текущего входа. Если сервер его не прислал, профиль
    // подтянет имя заново по user_id, а не покажет имя прошлого менеджера.
    if (fullName != null && fullName.trim().isNotEmpty) {
      await prefs.setString('user_name', fullName.trim());
    } else {
      await prefs.remove('user_name');
    }

    // Корзины другого менеджера убираем сразу, чтобы значок не показывал
    // чужое количество, пока новые корзины грузятся с сервера.
    final owner = prefs.getString(_cartsOwnerKey);
    if (userId == null || owner != userId) {
      await CartLocalStore.clearAll();
    }
    if (userId != null) await prefs.setString(_cartsOwnerKey, userId);

    refreshCarts(userId);
  }

  /// Вызывать при выходе из аккаунта.
  static Future<void> onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    await prefs.remove('session_cookies');
    await prefs.remove(_cartsOwnerKey);
    await CartLocalStore.clearAll();
  }

  /// Подтягивает корзины менеджера с сервера в фоне. Значок корзины
  /// обновится сам, когда они сохранятся локально.
  static void refreshCarts(String? userId) {
    final managerId = int.tryParse(userId ?? '');
    if (managerId == null) return;
    () async {
      try {
        await CartApiServiceOffline(dio: Dio()).loadCarts(managerId: managerId);
      } catch (e) {
        debugPrint('AccountSession.refreshCarts: $e');
      }
    }();
  }
}
