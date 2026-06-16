import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart';
import 'package:offlinesvet/customer/customer.dart';

/// Показывает анкету "Новый клиент" как модальный bottom sheet.
/// Возвращает true, если клиент был выбран/создан и сохранён как активный.
Future<bool?> showNewCustomerDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const NewCustomerSheet(),
  );
}

class NewCustomerSheet extends StatefulWidget {
  const NewCustomerSheet({super.key});

  @override
  State<NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<NewCustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _commentController = TextEditingController();

  final _bitrixService = BitrixService(dio: Dio());

  CustomerType _type = CustomerType.client;
  String _sourceId = defaultSourceId;
  bool _loading = false;
  String? _error;

  // Если телефон совпал с существующим контактом — храним найденный список здесь
  List<CustomerSearchResult>? _existingMatches;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
      _existingMatches = null;
    });

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    try {
      // Шаг 1: проверяем, есть ли уже контакт с таким телефоном
      final matches = await _bitrixService.searchContactsByPhone(phone);

      if (matches.isNotEmpty) {
        setState(() {
          _existingMatches = matches;
          _loading = false;
        });
        return;
      }

      // Шаг 2: контакта нет — создаём контакт, затем лид
      final contactId = await _bitrixService.createContact(
        name: name,
        phone: phone,
      );

      final leadId = await _bitrixService.createLead(
        contactId: contactId,
        name: name,
        phone: phone,
        type: _type,
        comment: _commentController.text.trim(),
        sourceId: _sourceId,
      );

      final customer = Customer(
        contactId: contactId,
        leadId: leadId,
        name: name,
        phone: phone,
        type: _type,
        selectedAt: DateTime.now(),
      );

      await CustomerStorage.setActive(customer);

      if (!mounted) return;
      Navigator.of(context).pop(true);
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

  /// Менеджер подтвердил выбор уже существующего контакта из найденных совпадений.
  Future<void> _selectExisting(CustomerSearchResult match) async {
    final customer = Customer(
      contactId: match.contactId,
      leadId: null, // лид не создаём — клиент уже существует
      name: match.name,
      lastName: match.lastName,
      phone: match.phone,
      type: _type,
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
        child: _existingMatches != null
            ? _buildExistingMatches()
            : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Новый клиент',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Имя *',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Укажите имя' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон *',
              border: OutlineInputBorder(),
              hintText: '+7 (___) ___-__-__',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Укажите телефон' : null,
          ),
          const SizedBox(height: 16),

          Text('Тип клиента *', style: Theme.of(context).textTheme.bodyMedium),
          Row(
            children: [
              Expanded(
                child: RadioListTile<CustomerType>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Клиент'),
                  value: CustomerType.client,
                  groupValue: _type,
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
              Expanded(
                child: RadioListTile<CustomerType>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Дизайнер'),
                  value: CustomerType.designer,
                  groupValue: _type,
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            initialValue: _sourceId,
            decoration: const InputDecoration(
              labelText: 'Источник (необязательно)',
              border: OutlineInputBorder(),
            ),
            items: leadSources.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _sourceId = v ?? defaultSourceId),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _commentController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Комментарий',
              border: OutlineInputBorder(),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Создать'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingMatches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Клиент с таким номером уже существует',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ..._existingMatches!.map(
          (m) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(m.fullName),
              subtitle: Text(m.phone),
              trailing: FilledButton(
                onPressed: () => _selectExisting(m),
                child: const Text('Выбрать'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => setState(() => _existingMatches = null),
            child: const Text('Отмена'),
          ),
        ),
      ],
    );
  }
}
