import 'package:flutter/material.dart';
import 'package:offlinesvet/customer/models/customer_model.dart';

class ClientCabinetScreen extends StatelessWidget {
  const ClientCabinetScreen({super.key, required this.customer});
  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Кабинет клиента', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: customer == null
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_off_outlined, size: 60, color: Colors.grey),
                SizedBox(height: 16),
                Text('Клиент не выбран',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black54)),
                SizedBox(height: 8),
                Text('Выберите клиента в главном меню',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Заголовок
                const Text(
                  'Текущий клиент',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Карточка клиента
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(children: [
                    // Аватар
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFE8F5E9),
                          radius: 28,
                          child: Icon(
                            customer!.isCompany ? Icons.business_outlined : Icons.person,
                            color: const Color(0xFF4CAF50),
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer!.fullName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                customer!.isCompany ? 'Компания' : customer!.type.label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4CAF50),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        )),
                      ]),
                    ),

                    const Divider(height: 1),

                    // Поля
                    if (!customer!.isCompany && (customer!.phone ?? '').isNotEmpty)
                      _InfoTile(
                        icon: Icons.phone_outlined,
                        label: 'Телефон',
                        value: customer!.phone ?? '',
                      ),

                    if (customer!.isCompany && (customer!.bin ?? '').isNotEmpty)
                      _InfoTile(
                        icon: Icons.badge_outlined,
                        label: 'БИН/ИИН',
                        value: customer!.bin ?? '',
                      ),

                    _InfoTile(
                      icon: Icons.info_outline,
                      label: 'Тип',
                      value: customer!.isCompany ? 'Компания' : 'Клиент',
                      isLast: true,
                    ),
                  ]),
                ),
              ],
            ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 15)),
          ]),
        ]),
      ),
      if (!isLast) const Divider(height: 1, indent: 48),
    ]);
  }
}
