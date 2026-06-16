import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/customer/models/customer_model.dart';

/// Хранит список клиентов, с которыми работал менеджер, и текущего
/// активного клиента — по аналогии с будущей мультикорзиной
/// (HL-блок Multibaskets на prons.kz): один менеджер -> много клиентов,
/// у каждого своя "корзина" (пока без товаров).
///
/// Список привязывается к auth_token менеджера (namespace), так как
/// в текущем API login.php/check.php нет стабильного manager_id —
/// другого идентификатора менеджера на клиенте сейчас нет.
class CustomerStorage {
  static const _tokenKey = 'auth_token';
  static String _customersKey(String token) => 'customers_$token';
  static String _activeIdKey(String token) => 'active_customer_id_$token';

  static Future<String?> _currentToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Список всех клиентов, выбранных/созданных текущим менеджером.
  static Future<List<Customer>> loadAll() async {
    final token = await _currentToken();
    if (token == null) return [];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customersKey(token));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('CustomerStorage.loadAll: ошибка парсинга: $e');
      return [];
    }
  }

  /// Текущий активный клиент (для которого собирается корзина), либо null.
  static Future<Customer?> loadActive() async {
    final token = await _currentToken();
    if (token == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final activeKey = prefs.getString(_activeIdKey(token));
    if (activeKey == null) return null;

    final all = await loadAll();
    for (final c in all) {
      if (c.storageKey == activeKey) return c;
    }
    return null;
  }

  /// Добавляет/обновляет клиента в списке менеджера и делает его активным.
  /// Используется как при создании нового контакта+лида, так и при выборе
  /// уже существующего контакта/компании — в обоих случаях он становится текущим.
  static Future<void> setActive(Customer customer) async {
    final token = await _currentToken();
    if (token == null) {
      debugPrint('CustomerStorage.setActive: нет auth_token, отмена');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();

    final idx = all.indexWhere((c) => c.storageKey == customer.storageKey);
    if (idx >= 0) {
      all[idx] = customer;
    } else {
      all.add(customer);
    }

    final encoded = jsonEncode(all.map((c) => c.toJson()).toList());
    await prefs.setString(_customersKey(token), encoded);
    await prefs.setString(_activeIdKey(token), customer.storageKey);
  }

  /// Очищает список клиентов текущего менеджера (например, при логауте).
  static Future<void> clearAll() async {
    final token = await _currentToken();
    if (token == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customersKey(token));
    await prefs.remove(_activeIdKey(token));
  }
}
