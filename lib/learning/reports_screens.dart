import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/catalog/product_list/widgets/product_tile.dart';
import 'package:offlinesvet/learning/web_pages.dart';
import 'package:offlinesvet/repositories/products/products.dart';

const _green = Color(0xFF4CAF50);
const _bg = Color(0xFFF3F2F7);

PreferredSizeWidget _bar(String t) => AppBar(
      backgroundColor: _green,
      foregroundColor: Colors.white,
      centerTitle: true,
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
    );

/// Запросы к manager_reports.php (страницы «Отчёты менеджеров», «Лидеры
/// продаж», «Отчёты» сайта offline.svet.kz).
class ReportsApi {
  static const _url = 'https://prons.kz/ajax/offlinesvet/manager_reports.php';
  final _dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 3)));

  Future<Map<String, dynamic>> call(String action, [Map<String, String> p = const {}]) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await _dio.post(_url,
          data: FormData.fromMap({'token': prefs.getString('auth_token') ?? '', 'action': action, ...p}),
          options: Options(responseType: ResponseType.plain, validateStatus: (s) => s != null));
      final d = jsonDecode(r.data as String);
      if (d is Map && d['result'] is Map) return Map<String, dynamic>.from(d['result'] as Map);
      throw Exception((d is Map ? d['error'] : null) ?? 'Ошибка сервера (${r.statusCode})');
    } on DioException {
      throw Exception('Нет подключения к интернету');
    }
  }
}

/// Какие разделы доступны менеджеру — по правам на папки сайта
/// offline.svet.kz (как в админке). Загружается при открытии меню.
class SectionsAccess {
  SectionsAccess._();
  static final ValueNotifier<Map<String, bool>?> value = ValueNotifier(null);
  static Future<void>? _loading;

  static bool can(String key) => value.value?[key] == true;

  static Future<void> load() {
    return _loading ??= () async {
      try {
        final r = await ReportsApi().call('access');
        value.value = r.map((k, v) => MapEntry(k, v == true));
      } catch (_) {
        // без интернета — оставляем прошлое значение
      } finally {
        _loading = null;
      }
    }();
  }
}

String _money(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

Widget _errorView(String e, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(e, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: _green), onPressed: retry, child: const Text('Повторить')),
        ]),
      ),
    );

// ───────────────────────── Отчёты менеджеров ─────────────────────────

/// «Статистика» — как /managers_reports/: ссылка «Лидеры продаж» и
/// список менеджеров; по менеджеру — лиды по месяцам и его заказы.
class ManagerReportsScreen extends StatefulWidget {
  const ManagerReportsScreen({super.key});
  @override
  State<ManagerReportsScreen> createState() => _ManagerReportsScreenState();
}

class _ManagerReportsScreenState extends State<ManagerReportsScreen> {
  List<Map<String, dynamic>>? _managers;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ReportsApi().call('managers');
      if (mounted) setState(() => _managers = ((r['managers'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (_managers ?? []).where((m) => '${m['name']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Отчёты менеджеров'),
      body: _managers == null
          ? (_error != null ? _errorView(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.all(12), children: [
              if (SectionsAccess.can('top_items')) SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF438CCB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopItemsScreen())),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Лидеры продаж'),
                ),
              ),
              const SizedBox(height: 8),
              if (SectionsAccess.can('new_stats')) SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF16522),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewStatisticsScreen())),
                  icon: const Icon(Icons.query_stats),
                  label: const Text('Новая статистика'),
                ),
              ),
              const SizedBox(height: 8),
              // Выгрузки в Excel — как кнопки на сайте
              const Row(children: [
                Expanded(child: _ExportButton(type: 'leads', label: 'Лиды')),
                SizedBox(width: 6),
                Expanded(child: _ExportButton(type: 'leads_tablet', label: 'Лиды (планш.)')),
                SizedBox(width: 6),
                Expanded(child: _ExportButton(type: 'orders', label: 'Заказы')),
              ]),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Поиск менеджера', prefixIcon: const Icon(Icons.search), isDense: true, filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              ...list.map((m) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFFE8F5E9), child: Icon(Icons.person, color: _green)),
                      title: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ManagerReportScreen(id: m['id'] as int, name: '${m['name']}'))),
                    ),
                  )),
            ]),
    );
  }

}

/// Отчёт по менеджеру: лиды по месяцам и заказы (с фильтром по статусу).
class ManagerReportScreen extends StatefulWidget {
  const ManagerReportScreen({super.key, required this.id, required this.name});
  final int id;
  final String name;
  @override
  State<ManagerReportScreen> createState() => _ManagerReportScreenState();
}

class _ManagerReportScreenState extends State<ManagerReportScreen> {
  final _api = ReportsApi();
  List<Map<String, dynamic>>? _months;
  bool _leadsFound = true;
  String? _leadsError;

  List<Map<String, dynamic>>? _orders;
  Map<String, Map<String, dynamic>> _statuses = {};
  String? _ordersError;
  final Set<String> _statusFilter = {};

  @override
  void initState() {
    super.initState();
    _loadLeads();
    _loadOrders();
  }

  Future<void> _loadLeads() async {
    setState(() { _leadsError = null; _months = null; });
    try {
      final r = await _api.call('leads', {'id': '${widget.id}', 'name': widget.name});
      if (mounted) {
        setState(() {
          _months = ((r['months'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList().reversed.toList();
          _leadsFound = r['found'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _leadsError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadOrders() async {
    setState(() { _ordersError = null; _orders = null; });
    try {
      final r = await _api.call('orders', {'manager_id': '${widget.id}'});
      if (mounted) {
        setState(() {
          _orders = ((r['orders'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _statuses = {for (final s in (r['statuses'] as List? ?? [])) '${s['id']}': Map<String, dynamic>.from(s as Map)};
        });
      }
    } catch (e) {
      if (mounted) setState(() => _ordersError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Color _hex(String h) {
    final v = int.tryParse('FF${h.replaceAll('#', '')}', radix: 16);
    return v == null ? Colors.grey : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final orders = (_orders ?? []).where((o) => _statusFilter.isEmpty || _statusFilter.contains(o['status_id'])).toList();
    final total = orders.fold<double>(0, (s, o) => s + (o['price'] as num).toDouble());
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar(widget.name),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _card('Лиды', [
          if (_leadsError != null)
            _errorView(_leadsError!, _loadLeads)
          else if (_months == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: Column(children: [
              CircularProgressIndicator(), SizedBox(height: 8),
              Text('Считаем лиды в Битрикс24 — до минуты', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ])))
          else if (!_leadsFound)
            const Text('Менеджер не найден в Битрикс24 или в поле «Ответственный менеджер»', style: TextStyle(color: Colors.grey))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 38,
                columnSpacing: 14,
                columns: const [
                  DataColumn(label: Text('Месяц')),
                  DataColumn(label: Text('Анкета:\nкачеств.', style: TextStyle(fontSize: 12)), numeric: true),
                  DataColumn(label: Text('Анкета:\nнекачеств.', style: TextStyle(fontSize: 12)), numeric: true),
                  DataColumn(label: Text('CRM:\nкачеств.', style: TextStyle(fontSize: 12)), numeric: true),
                  DataColumn(label: Text('CRM:\nпрочие', style: TextStyle(fontSize: 12)), numeric: true),
                  DataColumn(label: Text('Всего'), numeric: true),
                ],
                rows: _months!.map((m) {
                  final t = (m['form_converted'] as int) + (m['form_junk'] as int) + (m['other_converted'] as int) + (m['other_not_converted'] as int);
                  return DataRow(cells: [
                    DataCell(Text('${m['month']}')),
                    DataCell(Text('${m['form_converted']}')),
                    DataCell(Text('${m['form_junk']}')),
                    DataCell(Text('${m['other_converted']}')),
                    DataCell(Text('${m['other_not_converted']}')),
                    DataCell(Text('$t', style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]);
                }).toList(),
              ),
            ),
        ]),
        _card('Заказы', [
          if (_ordersError != null)
            _errorView(_ordersError!, _loadOrders)
          else if (_orders == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else ...[
            Text('Всего заказов ${orders.length} на сумму ${_money(total)} ₸',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: _statuses.values.map((s) {
              final sel = _statusFilter.contains(s['id']);
              return FilterChip(
                label: Text('${s['name']}', style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.black87)),
                selected: sel,
                selectedColor: _green,
                checkmarkColor: Colors.white,
                onSelected: (v) => setState(() => v ? _statusFilter.add('${s['id']}') : _statusFilter.remove('${s['id']}')),
              );
            }).toList()),
            const Divider(height: 20),
            ...orders.take(300).map((o) {
              final st = _statuses['${o['status_id']}'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(flex: 3, child: Text('№${o['number']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(flex: 4, child: Text('${o['date']}', style: const TextStyle(fontSize: 12, color: Colors.black54))),
                  Expanded(flex: 4, child: Text('${_money(o['price'] as num)} ₸', textAlign: TextAlign.right)),
                  const SizedBox(width: 8),
                  Container(
                    width: 90,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: _hex('${st?['color'] ?? ''}').withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${st?['name'] ?? o['status_id']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ]),
              );
            }),
            if (orders.length > 300)
              Text('Показаны первые 300 из ${orders.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ]),
      ]),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );
}

// ───────────────────────── Лидеры продаж ─────────────────────────

/// «Лидеры продаж» — как /open/top-items.php: период, бренд, раздел →
/// топ-50 товаров по количеству заказов на сайте Света.
class TopItemsScreen extends StatefulWidget {
  const TopItemsScreen({super.key});
  @override
  State<TopItemsScreen> createState() => _TopItemsScreenState();
}

class _TopItemsScreenState extends State<TopItemsScreen> {
  final _api = ReportsApi();
  final _repo = ProductsRepository(dio: Dio());
  static const _periods = {'day': 'За последние сутки', 'week': 'За последнюю неделю', 'month': 'За последний месяц', 'year': 'За последний год'};
  String _period = 'day';
  String _brand = 'ALL';
  String _section = 'ALL';
  List<String> _brands = [];
  List<Map<String, dynamic>> _sections = [];
  List<Product>? _items;
  Map<String, int> _amounts = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api.call('top_meta').then((r) {
      if (!mounted) return;
      setState(() {
        _brands = ((r['brands'] as List?) ?? []).map((e) => '$e').toList();
        _sections = ((r['sections'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    }).catchError((_) {});
  }

  Future<void> _show() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _api.call('top_items', {'period': _period, 'brand': _brand, 'section_id': _section});
      final rows = ((r['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ids = rows.map((e) => '${e['id']}').toList();
      final products = ids.isEmpty ? <Product>[] : await _repo.getProductsByIds(ids);
      final byId = {for (final p in products) p.id: p};
      if (!mounted) return;
      setState(() {
        _amounts = {for (final e in rows) '${e['id']}': (e['amount'] as num).toInt()};
        _items = ids.map((id) => byId[id]).whereType<Product>().toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _select(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(labelText: label, filled: true, fillColor: Colors.white, isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
          items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.of(context).size.width >= 576 ? 3 : 2;
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Лидеры продаж'),
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverList(delegate: SliverChildListDelegate([
            _select('Период', _period, _periods, (v) => setState(() => _period = v)),
            _select('Бренд', _brand, {'ALL': 'Все', for (final b in _brands) b: b}, (v) => setState(() => _brand = v)),
            _select('Раздел', _section, {'ALL': 'Все', for (final s in _sections) '${s['id']}': '${s['name']}'},
                (v) => setState(() => _section = v)),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _loading ? null : _show,
                child: Text(_loading ? 'Считаем…' : 'Показать', style: const TextStyle(fontSize: 16)),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (_items != null && _items!.isEmpty && !_loading)
              const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: Text('Нет продаж за этот период', style: TextStyle(color: Colors.grey)))),
          ])),
        ),
        if (_items != null && _items!.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.56),
              delegate: SliverChildBuilderDelegate((context, i) {
                final p = _items![i];
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${i + 1} место · в заказах: ${_amounts[p.id] ?? 0}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _green)),
                  ),
                  Expanded(child: ProductTile(product: p)),
                ]);
              }, childCount: _items!.length),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────── Отчёты (Power BI) ─────────────────────────

/// «Отчёты» — как /reports/: отчёты Power BI, доступ — как на сайте.
class BiReportsScreen extends StatefulWidget {
  const BiReportsScreen({super.key});
  @override
  State<BiReportsScreen> createState() => _BiReportsScreenState();
}

class _BiReportsScreenState extends State<BiReportsScreen> {
  List<Map<String, dynamic>>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ReportsApi().call('reports');
      if (mounted) setState(() => _reports = ((r['reports'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Отчёты'),
      body: _reports == null
          ? (_error != null ? _errorView(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : _reports!.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Нет доступа к отчётам. Доступ выдаёт администратор.', textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.all(12), children: _reports!.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.insights, color: _green, size: 30),
                      title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => WebPageScreen(title: '${r['name']}', url: '${r['url']}', allowAnyHost: true))),
                    ),
                  )).toList()),
    );
  }
}

// ───────────────────────── Выгрузка в Excel ─────────────────────────

class _ExportButton extends StatefulWidget {
  const _ExportButton({required this.type, required this.label});
  final String type;
  final String label;
  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Формируем отчёт — это может занять несколько минут')));
    try {
      final r = await ReportsApi().call('export_link', {'type': widget.type});
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/svet_${widget.type}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final resp = await Dio(BaseOptions(receiveTimeout: const Duration(minutes: 10)))
          .download('${r['url']}', path, options: Options(validateStatus: (s) => s != null));
      final f = File(path);
      final head = await f.openRead(0, 2).first;
      if (resp.statusCode != 200 || head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) {
        throw Exception('сервер не вернул файл Excel');
      }
      await Share.shareXFiles([XFile(path)], text: 'Отчёт: ${widget.label}');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось выгрузить: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _busy ? null : _run,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.grid_on, size: 16),
                  const SizedBox(width: 4),
                  Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                ]),
        ),
      );
}

// ───────────────────────── Новая статистика ─────────────────────────

/// «Новая статистика» — как /statistics/: менеджеры по городам.
class NewStatisticsScreen extends StatefulWidget {
  const NewStatisticsScreen({super.key});
  @override
  State<NewStatisticsScreen> createState() => _NewStatisticsScreenState();
}

class _NewStatisticsScreenState extends State<NewStatisticsScreen> {
  List<Map<String, dynamic>>? _cities;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ReportsApi().call('new_managers');
      if (mounted) setState(() => _cities = ((r['cities'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Статистика'),
      body: _cities == null
          ? (_error != null ? _errorView(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.all(12), children: _cities!.map((c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text('${c['city']}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: (c['managers'] as List).map((m) => ActionChip(
                        backgroundColor: const Color(0xFF4A5BC9),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        label: Text('${m['name']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => NewStatsDetailScreen(id: m['id'] as int, name: '${m['name']}', lastFirst: '${m['last_first']}'))),
                      )).toList()),
                  const SizedBox(height: 12),
                ],
              )).toList()),
    );
  }
}

class NewStatsDetailScreen extends StatefulWidget {
  const NewStatsDetailScreen({super.key, required this.id, required this.name, required this.lastFirst});
  final int id;
  final String name;
  final String lastFirst;
  @override
  State<NewStatsDetailScreen> createState() => _NewStatsDetailScreenState();
}

class _NewStatsDetailScreenState extends State<NewStatsDetailScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  final Set<String> _statusFilter = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _error = null; _d = null; });
    try {
      final r = await ReportsApi().call('new_stats', {'manager_id': '${widget.id}', 'last_first': widget.lastFirst});
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Color _hex(String h) {
    final v = int.tryParse('FF${h.replaceAll('#', '')}', radix: 16);
    return v == null ? Colors.grey : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar(widget.name),
      body: d == null
          ? (_error != null ? _errorView(_error!, _load) : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 8),
              Text('Считаем лиды и заказы…', style: TextStyle(color: Colors.grey)),
            ])))
          : _content(d),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final leads = ((d['leads'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final statuses = {for (final s in (d['statuses'] as List? ?? [])) '${s['id']}': Map<String, dynamic>.from(s as Map)};
    final orders = ((d['orders'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map))
        .where((o) => _statusFilter.isEmpty || _statusFilter.contains(o['status_id'])).toList();
    final total = orders.fold<double>(0, (s, o) => s + (o['price'] as num).toDouble());
    Widget card(String t, List<Widget> ch) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...ch,
          ]),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      card('Лиды', [
        if (d['found'] != true)
          const Text('Менеджер не найден в Битрикс24', style: TextStyle(color: Colors.grey))
        else if (leads.isEmpty)
          const Text('Лидов нет', style: TextStyle(color: Colors.grey))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40, dataRowMinHeight: 34, dataRowMaxHeight: 38, columnSpacing: 14,
              columns: const [
                DataColumn(label: Text('Месяц')),
                DataColumn(label: Text('CRM:\nкачеств.', style: TextStyle(fontSize: 12)), numeric: true),
                DataColumn(label: Text('CRM:\nнекачеств.', style: TextStyle(fontSize: 12)), numeric: true),
                DataColumn(label: Text('Планшет:\nкачеств.', style: TextStyle(fontSize: 12)), numeric: true),
                DataColumn(label: Text('Планшет:\nнекачеств.', style: TextStyle(fontSize: 12)), numeric: true),
              ],
              rows: leads.map((m) => DataRow(cells: [
                    DataCell(Text('${m['month']}')),
                    DataCell(Text('${m['crm_converted']}')),
                    DataCell(Text('${m['crm_junk']}')),
                    DataCell(Text('${m['tablet_converted']}')),
                    DataCell(Text('${m['tablet_junk']}')),
                  ])).toList(),
            ),
          ),
      ]),
      card('Заказы', [
        Text('Всего заказов ${orders.length} на сумму ${_money(total)} ₸', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: statuses.values.map((s) {
          final sel = _statusFilter.contains(s['id']);
          return FilterChip(
            label: Text('${s['name']}', style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.black87)),
            selected: sel, selectedColor: _green, checkmarkColor: Colors.white,
            onSelected: (v) => setState(() => v ? _statusFilter.add('${s['id']}') : _statusFilter.remove('${s['id']}')),
          );
        }).toList()),
        const Divider(height: 20),
        ...orders.take(300).map((o) {
          final st = statuses['${o['status_id']}'];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(flex: 3, child: Text('№${o['number']}', style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(flex: 4, child: Text('${o['date']}', style: const TextStyle(fontSize: 12, color: Colors.black54))),
              Expanded(flex: 4, child: Text('${_money(o['price'] as num)} ₸', textAlign: TextAlign.right)),
              const SizedBox(width: 8),
              Container(
                width: 90,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: _hex('${st?['color'] ?? ''}').withValues(alpha: 0.25), borderRadius: BorderRadius.circular(6)),
                child: Text('${st?['name'] ?? o['status_id']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
              ),
            ]),
          );
        }),
      ]),
    ]);
  }
}

// ───────────────────────── Уроки ─────────────────────────

String _lessonPage(String body) => '<!DOCTYPE html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<style>body{margin:0;padding:14px;font-family:-apple-system,Roboto,sans-serif;color:#222;line-height:1.5}'
    'img,video,iframe{max-width:100%;height:auto} table{max-width:100%;display:block;overflow-x:auto}</style>'
    '</head><body>$body</body></html>';

/// «Уроки» — курс модуля «Обучение» (как /obuchenie_svet/uroki/): разделы и
/// уроки, по нажатию — текст урока. Тесты не переносим.
class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});
  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ReportsApi().call('lessons');
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Уроки'),
      body: d == null
          ? (_error != null ? _errorView(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.all(12), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text('${d['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if ('${d['description_html']}'.trim().isNotEmpty)
                _tile('Описание курса', Icons.info_outline, 0, () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => WebPageScreen(title: 'Описание курса', html: _lessonPage('${d['description_html']}'))))),
              ...((d['items'] as List?) ?? []).map((e) {
                final it = Map<String, dynamic>.from(e as Map);
                final chapter = it['is_chapter'] == true;
                return _tile('${it['name']}', chapter ? Icons.folder_outlined : Icons.article_outlined,
                    ((it['depth'] as num?)?.toInt() ?? 1) - 1,
                    () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => LessonScreen(id: it['id'] as int, name: '${it['name']}'))));
              }),
            ]),
    );
  }

  Widget _tile(String title, IconData icon, int indent, VoidCallback onTap) => Container(
        margin: EdgeInsets.only(bottom: 6, left: 16.0 * indent.clamp(0, 4)),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(icon, color: _green),
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          onTap: onTap,
        ),
      );
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.id, required this.name});
  final int id;
  final String name;
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await ReportsApi().call('lesson', {'id': '${widget.id}'});
      if (!mounted) return;
      final body = '${r['html']}'.trim().isEmpty
          ? '<p style="color:#888">В этом разделе нет текста — откройте уроки внутри.</p>'
          : '${r['html']}';
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => WebPageScreen(title: widget.name, html: _lessonPage(body))));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: _bar(widget.name),
        body: _error != null ? _errorView(_error!, _load) : const Center(child: CircularProgressIndicator()),
      );
}
