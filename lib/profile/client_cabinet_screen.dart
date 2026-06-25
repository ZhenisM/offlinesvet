import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:offlinesvet/common/animated_search_bar.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/customer/customer.dart';
import 'package:offlinesvet/profile/client_orders_screen.dart';

class ClientCabinetScreen extends StatefulWidget {
  const ClientCabinetScreen({super.key, required this.customer});
  final Customer? customer;

  @override
  State<ClientCabinetScreen> createState() => _ClientCabinetScreenState();
}

class _ClientCabinetScreenState extends State<ClientCabinetScreen> {
  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';
  final _dio = Dio();

  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) _loadClientInfo();
  }

  Future<void> _loadClientInfo() async {
    setState(() { _loading = true; _error = null; });
    try {
      final c = widget.customer!;
      final params = <String, dynamic>{};
      if (c.isCompany) {
        params['name'] = c.fullName;
        params['is_company'] = 1;
      } else {
        params['phone'] = c.phone ?? '';
        params['name'] = c.fullName;
      }

      final response = await _dio.get(
        '$_baseUrl/get_client_info.php',
        queryParameters: params,
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      setState(() { _data = json; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmt(dynamic v) {
    final n = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    final s = n.toString().split('');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₸';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('О клиенте', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: false,
        actions: [
          const AnimatedSearchBar(),
          const SizedBox(width: 4),
        ],
      ),
      body: widget.customer == null
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_off_outlined, size: 60, color: Colors.grey),
                SizedBox(height: 16),
                Text('Клиент не выбран',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black54)),
              ]),
            )
          : _buildBody(),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.profile),
    );
  }

  Widget _buildBody() {
    final c = widget.customer!;
    final deals = _data?['deals'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Блок: Текущий клиент
        _SectionCard(
          title: 'Текущий клиент',
          child: Column(children: [
            _InfoRow(label: 'Имя', value: c.fullName),
            if (!c.isCompany && (c.phone ?? '').isNotEmpty)
              _InfoRow(label: 'Телефон', value: c.phone ?? ''),
            if (c.isCompany && (c.bin ?? '').isNotEmpty)
              _InfoRow(label: 'БИН/ИИН', value: c.bin ?? ''),
            _InfoRow(label: 'Тип', value: c.isCompany ? 'Компания' : c.type.label, isLast: true),
          ]),
        ),

        const SizedBox(height: 12),

        // Блок: Сделки клиента
        _SectionCard(
          title: 'Сделки клиента',
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        TextButton(onPressed: _loadClientInfo, child: const Text('Повторить')),
                      ]),
                    )
                  : Column(children: [
                      _InfoRow(label: 'Сумма', value: _fmt(deals['total_price'] ?? 0)),
                      _InfoRow(label: 'Количество', value: '${deals['total_count'] ?? 0}'),
                      _InfoRow(
                        label: 'Последний менеджер',
                        value: deals['last_manager']?.toString().isNotEmpty == true
                            ? deals['last_manager'].toString()
                            : '—',
                        isLast: true,
                      ),
                    ]),
        ),

        const SizedBox(height: 20),

        // Кнопка: Все заказы клиента
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClientOrdersScreen(customer: widget.customer!),
            ),
          ),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50),
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Все заказы клиента',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        const Divider(height: 1),
        child,
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.isLast = false});
  final String label, value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 15)),
          ]),
        ),
      ),
      if (!isLast) const Divider(height: 1),
    ]);
  }
}
