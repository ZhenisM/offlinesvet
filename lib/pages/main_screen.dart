import 'package:flutter/material.dart';
import 'package:offlinesvet/auth/auth_service.dart';
import 'package:offlinesvet/customer/customer.dart';
import 'package:offlinesvet/customer/view/new_customer_dialog.dart';
import 'package:offlinesvet/customer/view/search_customer_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Customer? _activeCustomer;
  bool _loadingCustomer = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCustomer();
  }

  Future<void> _loadActiveCustomer() async {
    final customer = await CustomerStorage.loadActive();
    if (!mounted) return;
    setState(() {
      _activeCustomer = customer;
      _loadingCustomer = false;
    });
  }

  Future<void> _openNewCustomer() async {
    final selected = await showNewCustomerDialog(context);
    if (selected == true) {
      _loadActiveCustomer();
    }
  }

  Future<void> _openSearchCustomer() async {
    final selected = await showSearchCustomerDialog(context);
    if (selected == true) {
      _loadActiveCustomer();
    }
  }

  Future<void> _confirmLogout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Выход"),
        content: Text("Вы уверены, что хотите выйти?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Отмена"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Выйти"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Вы вышли из аккаунта")),
      );
      await Future.delayed(Duration(milliseconds: 300));

      await AuthService.logout();

      if (!context.mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/auth',
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Offline-svet'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.logout_outlined),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildActiveCustomerCard(),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _openNewCustomer,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Новый клиент'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _openSearchCustomer,
              icon: const Icon(Icons.search),
              label: const Text('Найти клиента'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/products-list');
              },
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Каталог'),
              style: ElevatedButton.styleFrom(
                elevation: 2,
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCustomerCard() {
    if (_loadingCustomer) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_activeCustomer == null) {
      return Card(
        color: Colors.grey.shade100,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Клиент не выбран',
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ),
      );
    }

    final customer = _activeCustomer!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: const Icon(Icons.person, color: Color(0xFF005095)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Текущий клиент',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    customer.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${customer.phone} · ${customer.type.label}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
