import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/customer/customer_storage.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.fromProfile = false});
  final bool fromProfile;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';
  final _dio = Dio();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) throw Exception('Не удалось определить менеджера');

      final response = await _dio.get(
        '$_baseUrl/get_manager_stats.php',
        queryParameters: {'manager_id': managerId},
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
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Мои успехи',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: widget.fromProfile ? null : const AppBottomNavBar(currentTab: AppBottomTab.profile),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ]),
        ),
      );
    }

    final d = _data!;
    final manager   = d['manager'] as Map<String, dynamic>? ?? {};
    final dateToday = d['date_today'] as String? ?? '';
    final last      = d['LAST_MONTH']     as Map<String, dynamic>? ?? {};
    final pre       = d['PRE_LAST_MONTH'] as Map<String, dynamic>? ?? {};
    final statuses  = last['STATUSES'] as List<dynamic>? ?? [];

    return RefreshIndicator(
      color: const Color(0xFF4CAF50),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Шапка — имя и дата
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE8F5E9),
                radius: 24,
                child: const Icon(Icons.person, color: Color(0xFF4CAF50), size: 28),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  manager['NAME']?.toString() ?? 'Менеджер',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  dateToday,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ]),
            ]),
          ),

          const SizedBox(height: 12),

          // Сводная таблица
          _SectionCard(
            title: 'Общая статистика',
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.6),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.2),
              },
              children: [
                _tableHeader(['', 'Прошлый\nмесяц', 'Этот\nмесяц']),
                _tableRow([
                  'Заказов',
                  pre['TOTAL_AMOUNT']?.toString() ?? '0',
                  last['TOTAL_AMOUNT']?.toString() ?? '0',
                ], isEven: false),
                _tableRow([
                  'На сумму',
                  '${_fmt(pre['TOTAL_PRICE'])} ₸',
                  '${_fmt(last['TOTAL_PRICE'])} ₸',
                ], isEven: true),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Оплачено
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Оплачено за месяц',
                  style: TextStyle(fontSize: 14, color: Colors.black87)),
                Text(
                  '${_fmt(last['TOTAL_PAID_PRICE'])} ₸',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
          ),

          // Статусы — если есть
          if (statuses.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'По статусам (этот месяц)',
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(0.8),
                  2: FlexColumnWidth(1.2),
                },
                children: [
                  _tableHeader(['Статус', 'Шт', 'Сумма']),
                  ...statuses.asMap().entries.map((e) {
                    final s = e.value as Map<String, dynamic>;
                    return _tableRow([
                      s['DISPLAY_STATUS']?.toString() ?? '',
                      s['AMOUNT']?.toString() ?? '0',
                      '${_fmt(s['PRICE'])} ₸',
                    ], isEven: e.key % 2 == 0);
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  TableRow _tableHeader(List<String> cells) {
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      children: cells.map((c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(c,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
          textAlign: cells.indexOf(c) == 0 ? TextAlign.left : TextAlign.right),
      )).toList(),
    );
  }

  TableRow _tableRow(List<String> cells, {required bool isEven}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isEven ? const Color(0xFFFAFAFA) : Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      children: cells.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(e.value,
          style: const TextStyle(fontSize: 13),
          textAlign: e.key == 0 ? TextAlign.left : TextAlign.right),
      )).toList(),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: child,
          ),
        ],
      ),
    );
  }
}
