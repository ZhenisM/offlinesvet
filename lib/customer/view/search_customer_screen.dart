import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart';
import 'package:offlinesvet/cart/cart.dart';
import 'package:offlinesvet/customer/customer.dart';

enum _SearchEntity { contact, company }

/// Полноценный экран поиска клиента — открывается через Navigator.push.
/// Возвращает true, если клиент был найден и выбран как активный.
class SearchCustomerScreen extends StatefulWidget {
  const SearchCustomerScreen({super.key});

  @override
  State<SearchCustomerScreen> createState() => _SearchCustomerScreenState();
}

class _SearchCustomerScreenState extends State<SearchCustomerScreen> {
  _SearchEntity _entity = _SearchEntity.contact;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Найти клиента')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Переключатель Контакт / Компания — как на сайте
            Row(
              children: [
                Expanded(
                  child: _EntityToggleButton(
                    label: 'Контакт',
                    selected: _entity == _SearchEntity.contact,
                    onTap: () => setState(() => _entity = _SearchEntity.contact),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _EntityToggleButton(
                    label: 'Компания',
                    selected: _entity == _SearchEntity.company,
                    onTap: () => setState(() => _entity = _SearchEntity.company),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _entity == _SearchEntity.contact
                  ? const _ContactSearchView()
                  : const _CompanySearchView(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityToggleButton extends StatelessWidget {
  const _EntityToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF3C5AEC) : Colors.white,
        foregroundColor: selected ? Colors.white : Colors.black,
        side: const BorderSide(color: Color(0xFF3C5AEC)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label),
    );
  }
}

// ===========================================================
// Поиск контакта (физлицо) по телефону — через Bitrix24
// ===========================================================

class _ContactSearchView extends StatefulWidget {
  const _ContactSearchView();

  @override
  State<_ContactSearchView> createState() => _ContactSearchViewState();
}

class _ContactSearchViewState extends State<_ContactSearchView> {
  final _phoneController = TextEditingController();
  final _bitrixService = BitrixService(dio: Dio());
  final _cartApiService = CartApiService(dio: Dio());

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
    setState(() {
      _loading = true;
      _error = null;
    });

    final customer = Customer(
      contactId: match.contactId,
      isCompany: false,
      leadId: null,
      name: match.name,
      lastName: match.lastName,
      phone: match.phone,
      type: CustomerType.client,
      selectedAt: DateTime.now(),
    );

    try {
      await CustomerStorage.setActive(customer);

      final managerId = await CustomerStorage.currentManagerId();
      if (managerId != null) {
        await _cartApiService.createCart(
          managerId: managerId,
          customer: customer,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).pushReplacementNamed('/products-list');
    } on NoInternetException {
      setState(() {
        _error = 'Нет интернета';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Не удалось создать корзину для клиента';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      onPressed: _loading ? null : () => _select(m),
                      child: _loading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Выбрать'),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================
// Поиск компании по названию или БИН/ИИН — через prons.kz (HL CompanyList)
// ===========================================================

class _CompanySearchView extends StatefulWidget {
  const _CompanySearchView();

  @override
  State<_CompanySearchView> createState() => _CompanySearchViewState();
}

class _CompanySearchViewState extends State<_CompanySearchView> {
  final _titleController = TextEditingController();
  final _binController = TextEditingController();
  final _pronsApi = PronsApiService(dio: Dio());
  final _cartApiService = CartApiService(dio: Dio());

  bool _loading = false;
  String? _error;
  List<CompanySearchResult>? _results;

  @override
  void dispose() {
    _titleController.dispose();
    _binController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final title = _titleController.text.trim();
    final bin = _binController.text.trim();

    if (title.isEmpty && bin.isEmpty) {
      setState(() => _error = 'Введите название или БИН/ИИН');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });

    try {
      // БИН приоритетнее, если заполнен — это точный поиск.
      final results = bin.isNotEmpty
          ? await _pronsApi.searchCompanies(query: bin, byBin: true)
          : await _pronsApi.searchCompanies(query: title, byBin: false);

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
        _error = 'Не удалось выполнить поиск';
        _loading = false;
      });
    }
  }

  Future<void> _select(CompanySearchResult match) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final customer = Customer(
      companyId: match.companyId,
      isCompany: true,
      leadId: null,
      name: match.name,
      bin: match.bin,
      type: CustomerType.client,
      selectedAt: DateTime.now(),
    );

    try {
      await CustomerStorage.setActive(customer);

      final managerId = await CustomerStorage.currentManagerId();
      if (managerId != null) {
        await _cartApiService.createCart(
          managerId: managerId,
          customer: customer,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).pushReplacementNamed('/products-list');
    } on NoInternetException {
      setState(() {
        _error = 'Нет интернета';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Не удалось создать корзину для клиента';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Наименование',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _binController,
            keyboardType: TextInputType.number,
            maxLength: 12,
            decoration: const InputDecoration(
              labelText: 'БИН/ИИН',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
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
                  : const Text('Поиск'),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],

          if (_results != null) ...[
            const SizedBox(height: 16),
            Text(
              'Найдено компаний: ${_results!.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 8),
            if (_results!.isEmpty)
              const Text('Компания не найдена')
            else
              ..._results!.map(
                (m) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(m.name),
                    subtitle: Text(m.bin),
                    trailing: FilledButton(
                      onPressed: _loading ? null : () => _select(m),
                      child: _loading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Выбрать'),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
