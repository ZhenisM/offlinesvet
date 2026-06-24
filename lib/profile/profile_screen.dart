import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/auth/auth_service.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/customer/customer.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/profile/client_cabinet_screen.dart';
import 'package:offlinesvet/stats/stats_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _managerName = '';
  Customer? _activeCustomer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('user_name') ?? '';
    final customer = await CustomerStorage.loadActive();

    // Если имя не сохранено — запрашиваем с сервера через get_manager_stats
    if (name.isEmpty) {
      try {
        final managerId = await CustomerStorage.currentManagerId();
        if (managerId != null) {
          final dio = Dio();
          final response = await dio.get(
            'https://prons.kz/ajax/offlinesvet/get_manager_stats.php',
            queryParameters: {'manager_id': managerId},
            options: Options(responseType: ResponseType.plain),
          );
          final json = jsonDecode(response.data as String) as Map<String, dynamic>;
          final managerData = json['manager'] as Map<String, dynamic>? ?? {};
          name = managerData['NAME']?.toString() ?? '';
          // Кэшируем на будущее
          if (name.isNotEmpty) {
            await prefs.setString('user_name', name);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _managerName = name;
      _activeCustomer = customer;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/auth', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Профиль', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Блок менеджера + клиента
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Менеджер
                Row(children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    radius: 28,
                    child: Icon(Icons.person, color: Color(0xFF4CAF50), size: 32),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'Менеджер',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _managerName.isNotEmpty ? _managerName : '—',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ]),
                ]),

                // Разделитель
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),

                // Текущий клиент
                Row(children: [
                  CircleAvatar(
                    backgroundColor: Colors.grey.shade100,
                    radius: 28,
                    child: Icon(
                      _activeCustomer?.isCompany == true
                          ? Icons.business_outlined
                          : Icons.person_outline,
                      color: Colors.grey.shade500,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'Клиент',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _activeCustomer != null
                          ? _activeCustomer!.fullName
                          : 'Не выбран',
                      style: TextStyle(
                        fontSize: 15,
                        color: _activeCustomer != null
                            ? Colors.black87
                            : Colors.grey.shade400,
                      ),
                    ),
                  ]),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Три раздела
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              _MenuItem(
                icon: Icons.insert_chart_outlined,
                label: 'Мои успехи',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StatsScreen(fromProfile: true))),
              ),
              const Divider(height: 1, indent: 56),
              _MenuItem(
                icon: Icons.lightbulb_outline,
                label: 'Советы',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _TipsScreen())),
              ),
              const Divider(height: 1, indent: 56),
              _MenuItem(
                icon: Icons.person_outline,
                label: 'Кабинет клиента',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ClientCabinetScreen(customer: _activeCustomer))),
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // Кнопка выхода
          GestureDetector(
            onTap: _logout,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.logout_outlined, color: Colors.red, size: 22),
                const SizedBox(width: 14),
                const Text(
                  'Выйти',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.profile),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF4CAF50), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}

// Советы — заглушка
class _TipsScreen extends StatelessWidget {
  const _TipsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Советы', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lightbulb_outline, size: 60, color: Colors.grey),
          SizedBox(height: 16),
          Text('Раздел в разработке',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black54)),
          SizedBox(height: 8),
          Text('Советы появятся в следующем обновлении',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
      ),
    );
  }
}
