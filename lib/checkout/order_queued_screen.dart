import 'package:flutter/material.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

/// Экран после постановки заказа в офлайн-очередь.
/// В отличие от OrderSuccessScreen, здесь ещё нет настоящего order_id —
/// заказ реально создастся на сервере только когда появится интернет
/// и до него дойдёт очередь синхронизации (см. SyncService). Поэтому
/// здесь нет ни номера заказа, ни кнопки генерации КП.
class OrderQueuedScreen extends StatelessWidget {
  const OrderQueuedScreen({super.key, required this.clientName});

  final String clientName;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F2F7),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF9A825),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Заказ поставлен в очередь',
              style: TextStyle(fontWeight: FontWeight.w600)),
          centerTitle: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                      color: Color(0xFFF9A825),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_off_outlined, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Нет интернета — заказ поставлен в очередь',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(children: [
                  SizedBox(
                    width: 120,
                    child: Text('Клиент', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ),
                  Expanded(
                    child: Text(clientName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ]),
                const SizedBox(height: 16),
                Text(
                  'Заказ автоматически отправится на сервер, как только '
                  'появится подключение к интернету. Номер заказа и '
                  'документ КП станут доступны после этого — на экране '
                  'корзин появится уведомление, что заказ обработан.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                ),
              ]),
            ),
            const SizedBox(height: 28),
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
