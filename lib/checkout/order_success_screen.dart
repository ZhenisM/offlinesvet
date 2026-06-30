import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

  bool _generating = false;
  String? _error;

  Future<void> _generateKpClient() async {
    setState(() { _generating = true; _error = null; });

    try {
      final response = await _dio.get(
        '$_baseUrl/generate_kp_client.php',
        queryParameters: {'order_id': widget.orderId},
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data as List<int>;

      // Сохраняем во временную папку
      final dir = await getTemporaryDirectory();
      final safeClientName = widget.clientName.replaceAll(RegExp(r'[^\wа-яА-Я]'), '_');
      final fileName = 'KP_${safeClientName}_${widget.orderId}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      setState(() => _generating = false);

      // Открываем системное меню "Поделиться" — менеджер выбирает
      // сохранить в файлы, отправить в WhatsApp/Telegram и т.д.
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'КП для клиента ${widget.clientName}, заказ №${widget.orderId}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = 'Не удалось создать КП. Проверьте интернет.';
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

            // Кнопка КП-Клиент
            _DocumentButton(
              label: 'КП-Клиент',
              subtitle: 'Коммерческое предложение для клиента',
              icon: Icons.picture_as_pdf_outlined,
              loading: _generating,
              onTap: _generateKpClient,
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
