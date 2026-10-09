import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

/// Экран после успешного оформления заказа.
/// Заменяет всплывающее окно — открывается сразу после create_order.php.
class OrderSuccessScreen extends StatefulWidget {
  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    required this.clientName,
  });

  final int orderId;
  final String clientName;

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  static const _baseUrl = 'https://prons.kz/ajax/offlinesvet';
  final _dio = Dio();

  String? _error;

  /// Все КП как на сайте («Заказ сформирован»): NEW КП для клиента, Каз КП,
  /// Без итого, Для кассира, Астана КП, Клиент без скидки, Для дизайнеров и
  /// персональные. Список и ссылки (с hash-кодом заказа) выдаёт kp_links.php —
  /// добавить/убрать КП можно на сервере, без пересборки приложения.
  List<_KpDoc>? _docs;
  String? _docsError;
  String? _loadingDoc;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() { _docs = null; _docsError = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final response = await _dio.post(
        '$_baseUrl/kp_links.php',
        data: FormData.fromMap({'token': token, 'order_id': widget.orderId}),
        options: Options(responseType: ResponseType.plain, validateStatus: (s) => s != null),
      );
      final data = jsonDecode(response.data as String);
      if (data is Map && data['result'] is Map) {
        final list = ((data['result']['documents'] as List?) ?? [])
            .map((e) => _KpDoc(e['code'].toString(), e['title'].toString(), e['url'].toString(), e['filename'].toString()))
            .toList();
        if (mounted) setState(() => _docs = list);
      } else {
        if (mounted) setState(() => _docsError = (data is Map ? data['error'] : null)?.toString() ?? 'Не удалось загрузить список КП');
      }
    } catch (e) {
      if (mounted) setState(() => _docsError = 'Не удалось загрузить список КП: $e');
    }
  }

  /// Скачать PDF по ссылке и открыть системное меню «Поделиться» —
  /// чтобы отправить клиенту.
  Future<void> _openDoc(_KpDoc doc) async {
    if (_loadingDoc != null) return;
    setState(() { _loadingDoc = doc.code; _error = null; });
    try {
      final response = await _dio.get(
        doc.url,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 90)),
      );
      var bytes = response.data as List<int>;
      // PDF может начинаться не с первого байта: модуль печати иногда
      // выводит перед ним пробелы/переводы строк или предупреждения PHP.
      // Ищем сигнатуру %PDF в начале ответа и отрезаем всё до неё.
      final head = String.fromCharCodes(bytes.take(2048));
      final pdfAt = head.indexOf('%PDF');
      if (pdfAt < 0) {
        // Не PDF — показываем, что ответил сервер (обычно текст ошибки модуля).
        final text = utf8
            .decode(bytes.take(4000).toList(), allowMalformed: true)
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        debugPrint('KP ${doc.code}: ${response.statusCode} ${doc.url}\n$text');
        throw Exception('сервер вернул не PDF: ${text.isEmpty ? '(пустой ответ, код ${response.statusCode})' : text.substring(0, text.length > 300 ? 300 : text.length)}');
      }
      if (pdfAt > 0) bytes = bytes.sublist(pdfAt);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${doc.filename}');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _loadingDoc = null);
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${doc.title}, заказ №${widget.orderId}',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDoc = null;
        _error = 'Не удалось создать «${doc.title}»: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // блокируем системный "назад" — только через кнопку
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F2F7),
        appBar: AppBar(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Заказ оформлен',
              style: TextStyle(fontWeight: FontWeight.w600)),
          centerTitle: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Карточка с информацией о заказе
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Заказ успешно создан!',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _InfoRow(label: 'Номер заказа', value: '№${widget.orderId}'),
                const SizedBox(height: 8),
                _InfoRow(label: 'Клиент', value: widget.clientName),
              ]),
            ),

            const SizedBox(height: 20),

            const Text('Документы',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: Colors.black54)),
            const SizedBox(height: 10),

            ...?_docs?.map((d) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _DocumentButton(
                    label: d.title,
                    subtitle: 'КП по заказу, PDF',
                    icon: Icons.download_outlined,
                    loading: _loadingDoc == d.code,
                    onTap: () => _openDoc(d),
                  ),
                )),
            if (_docs == null && _docsError == null)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF4CAF50)))),
              ),
            if (_docsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Expanded(child: Text(_docsError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  TextButton(onPressed: _loadDocs, child: const Text('Повторить')),
                ]),
              ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],

            const SizedBox(height: 28),

            // Кнопка возврата в каталог
            SizedBox(
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF4CAF50)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/products-list', (_) => false),
                child: const Text('В каталог',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50))),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.cart),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 120,
        child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      ),
      Expanded(
        child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    ]);
  }
}

class _DocumentButton extends StatelessWidget {
  const _DocumentButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  final String label, subtitle;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
        ),
          child: loading
              ? const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: Color(0xFF4CAF50)),
          )
              : Icon(icon, color: Color(0xFF4CAF50), size: 24),
        ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]),
            ),
            if (!loading)
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}

class _KpDoc {
  final String code, title, url, filename;
  _KpDoc(this.code, this.title, this.url, this.filename);
}
