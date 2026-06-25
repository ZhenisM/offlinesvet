import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:offlinesvet/common/animated_search_bar.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/customer/customer.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/cart/cart_api_service.dart';
import 'package:offlinesvet/customer/prons_api_service.dart';

class ClientOrdersScreen extends StatefulWidget {
  const ClientOrdersScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';
  final _dio = Dio();

  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  bool _loadingMore = false;

  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore && _page < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _page = 1; _orders = []; });
    await _fetch(1);
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    await _fetch(_page + 1);
    setState(() => _loadingMore = false);
  }

  Future<void> _fetch(int page) async {
    try {
      final c = widget.customer;
      final params = <String, dynamic>{'page': page};
      if (c.isCompany) {
        params['name']       = c.fullName;
        params['is_company'] = 1;
      } else {
        params['phone'] = c.phone ?? '';
        params['name']  = c.fullName;
      }

      final response = await _dio.get(
        '$_baseUrl/get_client_orders.php',
        queryParameters: params,
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final newOrders = (json['orders'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      setState(() {
        if (page == 1) {
          _orders = newOrders;
        } else {
          _orders = [..._orders, ...newOrders];
        }
        _page       = page;
        _totalPages = (json['pages'] as num?)?.toInt() ?? 1;
      });
    } catch (e) {
      setState(() => _error = e.toString());
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

  // -------------------------------------------------------
  // Повторить заказ
  // -------------------------------------------------------
  Future<void> _repeatOrder(Map<String, dynamic> order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Повторить заказ ${order['id']}'),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Внимание!',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 8),
          Text('Товары из заказа будут добавлены в текущую корзину.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final managerId = await CustomerStorage.currentManagerId();
      if (managerId == null) throw Exception('Нет менеджера');

      final response = await _dio.post(
        '$_baseUrl/repeat_order.php',
        data: jsonEncode({'order_id': order['id'], 'manager_id': managerId}),
        options: Options(contentType: 'application/json', responseType: ResponseType.plain),
      );
      final result = jsonDecode(response.data as String) as Map<String, dynamic>;
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Товары добавлены в корзину'), backgroundColor: Color(0xFF4CAF50)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Ошибка'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // -------------------------------------------------------
  // Повторить на юрлицо
  // -------------------------------------------------------
  Future<void> _repeatOrderLegal(Map<String, dynamic> order) async {
    final nameCtrl = TextEditingController();
    final binCtrl  = TextEditingController();
    List<Map<String, dynamic>> companies = [];
    String? selectedCompanyId;
    bool searchDone = false;
    bool searching  = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF3F2F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Text('Повторить заказ №${order['id']} на Юр.лицо',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              _sheetInput(nameCtrl, 'Наименование'),
              const SizedBox(height: 10),
              _sheetInput(binCtrl, 'БИН/ИИН', keyboardType: TextInputType.number, maxLength: 12),
              const SizedBox(height: 12),

              GestureDetector(
                onTap: searching ? null : () async {
                  setS(() { searching = true; companies = []; searchDone = false; selectedCompanyId = null; });
                  try {
                    final pronsApi = PronsApiService(dio: Dio());
                    final q = binCtrl.text.trim().isNotEmpty ? binCtrl.text.trim() : nameCtrl.text.trim();
                    final res = await pronsApi.searchCompanies(query: q, byBin: binCtrl.text.trim().isNotEmpty);
                    setS(() {
                      companies = res.map((c) => {'id': c.companyId, 'name': c.name, 'bin': c.bin}).toList();
                      searchDone = true;
                      searching = false;
                    });
                  } catch (e) {
                    setS(() { searching = false; searchDone = true; });
                  }
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: searching
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.search, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Поиск компании', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ]),
                ),
              ),

              if (searchDone && companies.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 12),
                  child: Text('Ничего не найдено', style: TextStyle(color: Colors.grey))),

              if (companies.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Результаты поиска:', style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 6),
                ...companies.map((c) {
                  final isSelected = selectedCompanyId == c['id'].toString();
                  return GestureDetector(
                    onTap: () => setS(() => selectedCompanyId = c['id'].toString()),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? const Color(0xFF4CAF50) : Colors.white,
                            border: Border.all(
                              color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade300,
                            ),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${c['name']} [${c['bin']}]', style: const TextStyle(fontSize: 13))),
                      ]),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                if (selectedCompanyId != null)
                  GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        final managerId = await CustomerStorage.currentManagerId();
                        final response = await _dio.post(
                          '$_baseUrl/repeat_order.php',
                          data: jsonEncode({
                            'order_id': order['id'],
                            'manager_id': managerId,
                            'to_legal': true,
                            'company_id': selectedCompanyId,
                          }),
                          options: Options(contentType: 'application/json', responseType: ResponseType.plain),
                        );
                        final result = jsonDecode(response.data as String) as Map<String, dynamic>;
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(result['success'] == true ? 'Заказ повторён на юрлицо' : (result['error'] ?? 'Ошибка')),
                          backgroundColor: result['success'] == true ? const Color(0xFF4CAF50) : Colors.red,
                        ));
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                      }
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(color: const Color(0xFF4CAF50), borderRadius: BorderRadius.circular(28)),
                      alignment: Alignment.center,
                      child: const Text('Выбрать', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sheetInput(TextEditingController ctrl, String hint, {
    TextInputType keyboardType = TextInputType.text, int? maxLength,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true, fillColor: Colors.white,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Заказы клиента', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: false,
        actions: [
          const AnimatedSearchBar(),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ]))
              : _orders.isEmpty
                  ? const Center(child: Text('Нет заказов', style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      color: const Color(0xFF4CAF50),
                      onRefresh: _load,
                      child: GridView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: MediaQuery.of(context).size.width >= 576 ? 3 : 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: _orders.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _orders.length) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          return _OrderCard(
                            order: _orders[i],
                            onRepeat: () => _repeatOrder(_orders[i]),
                            onRepeatLegal: _orders[i]['person_type_id'] == 5
                                ? () => _repeatOrderLegal(_orders[i])
                                : null,
                            fmt: _fmt,
                          );
                        },
                      ),
                    ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.profile),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onRepeat,
    required this.onRepeatLegal,
    required this.fmt,
  });
  final Map<String, dynamic> order;
  final VoidCallback onRepeat;
  final VoidCallback? onRepeatLegal;
  final String Function(dynamic) fmt;

  @override
  Widget build(BuildContext context) {
    final statusName = order['status_name'] ?? order['status_id'] ?? '';
    final isCancelled = (order['status_id'] ?? '').toString().toUpperCase() == 'C' ||
                        statusName.toLowerCase().contains('отмен');
    final statusColor = isCancelled ? Colors.red : Colors.black87;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ID заказа
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              '${order['id']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),

          // Поля
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(label: 'Дата', value: order['date'] ?? ''),
                  _Field(label: 'Сумма', value: fmt(order['price'])),
                  _Field(label: 'Статус', value: statusName, valueColor: statusColor),
                  if ((order['manager'] ?? '').isNotEmpty)
                    _Field(label: 'Менеджер', value: order['manager']),
                  _Field(label: 'Тип плательщика', value: order['person_type'] ?? ''),
                  if ((order['client_name'] ?? '').isNotEmpty)
                    _Field(label: 'Клиент', value: order['client_name']),
                ],
              ),
            ),
          ),

          // Кнопка Действия
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: _ActionsMenu(
              onRepeat: onRepeat,
              onRepeatLegal: onRepeatLegal,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        Text(value,
          style: TextStyle(fontSize: 12, color: valueColor ?? Colors.black87),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.onRepeat, this.onRepeatLegal});
  final VoidCallback onRepeat;
  final VoidCallback? onRepeatLegal;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'repeat') onRepeat();
        if (v == 'repeat_legal' && onRepeatLegal != null) onRepeatLegal!();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Действия', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 16),
        ]),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'repeat',
          child: Row(children: [
            Icon(Icons.refresh, size: 18, color: Colors.black54),
            SizedBox(width: 8),
            Text('Повторить'),
          ]),
        ),
        if (onRepeatLegal != null)
          const PopupMenuItem(
            value: 'repeat_legal',
            child: Row(children: [
              Icon(Icons.arrow_forward, size: 18, color: Colors.black54),
              SizedBox(width: 8),
              Text('Повторить на юр.лицо'),
            ]),
          ),
      ],
    );
  }
}
