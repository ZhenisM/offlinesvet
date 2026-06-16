import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart';
import 'package:offlinesvet/customer/customer.dart';

/// Показывает диалог поиска клиента по телефону как модальный bottom sheet.
/// Возвращает true, если клиент был найден и выбран как активный.
Future<bool?> showSearchCustomerDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const SearchCustomerSheet(),
  );
}

class SearchCustomerSheet extends StatefulWidget {
  const SearchCustomerSheet({super.key});

  @override
  State<SearchCustomerSheet> createState() => _SearchCustomerSheetState();
}

class _SearchCustomerSheetState extends State<SearchCustomerSheet> {
  final _phoneController = TextEditingController();
  final _bitrixService = BitrixService(dio: Dio());

  bool _loading = false;
  String? _error;
  List<CustomerSearchResult>? _results;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Введите телефон');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });

    try {
      final results = await _bitrixService.searchContactsByPhone(phone);
      setState(() {
        _results = results;
        _loading = false;
      });
    } on NoInternetException {
      setState(() {
        _error = 'Нет интернета';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _select(CustomerSearchResult match) async {
    final customer = Customer(
      contactId: match.contactId,
      leadId: null,
      name: match.name,
      lastName: match.lastName,
      phone: match.phone,
      type: CustomerType.client,
      selectedAt: DateTime.now(),
    );

    await CustomerStorage.setActive(customer);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Найти клиента',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Найти'),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],

            if (_results != null) ...[
              const SizedBox(height: 16),
              Text(
                'Найдено клиентов: ${_results!.length}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 8),
              if (_results!.isEmpty)
                const Text('Клиент с таким номером не найден')
              else
                ..._results!.map(
                  (m) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(m.fullName),
                      subtitle: Text(m.phone),
                      trailing: FilledButton(
                        onPressed: () => _select(m),
                        child: const Text('Выбрать'),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
