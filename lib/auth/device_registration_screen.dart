import 'package:flutter/material.dart';
import 'package:offlinesvet/auth/badge_api.dart';

/// Регистрация планшета для входа по бейджу. Доступна только администратору.
class DeviceRegistrationScreen extends StatefulWidget {
  const DeviceRegistrationScreen({super.key});

  @override
  State<DeviceRegistrationScreen> createState() => _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  static const _green = Color(0xFF4CAF50);
  final _api = BadgeApi();
  final _name = TextEditingController();
  BadgeDevice? _device;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<BadgeDevice> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await job();
      if (!mounted) return;
      setState(() => _device = d);
      if (d.name != null && _name.text.isEmpty) _name.text = d.name!;
    } on BadgeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async => (await _api.me()).$2);

  Future<void> _register() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Укажите название, например «Шоурум Алматы, планшет 1»');
      return;
    }
    await _run(() => _api.registerDevice(name));
    if (mounted && _device?.registered == true && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Планшет зарегистрирован. Теперь на нём работает вход по бейджу.')));
    }
  }

  Future<void> _unregister() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить вход по бейджу?'),
        content: const Text('На этом планшете снова можно будет войти только по логину и паролю.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отключить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await _run(() => _api.unregisterDevice());
  }

  @override
  Widget build(BuildContext context) {
    final reg = _device?.registered == true;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Планшет для входа по бейджу'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(reg ? Icons.verified_outlined : Icons.tablet_android_outlined,
                  color: reg ? _green : Colors.grey, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _busy && _device == null
                      ? 'Проверяю…'
                      : reg
                          ? 'Зарегистрирован: ${_device!.name ?? ''}'
                          : 'Этот планшет не зарегистрирован',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Text(
            'На зарегистрированном планшете менеджеры входят, просто показав камере свой QR-бейдж. '
            'На других телефонах и планшетах бейдж не работает. Бейджи выдаются на странице '
            'prons.kz/ajax/offlinesvet/badge/.',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Название планшета',
              hintText: 'Шоурум Алматы, планшет 1',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _register,
              child: Text(reg ? 'Сохранить название' : 'Зарегистрировать планшет',
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (reg) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _unregister,
              child: const Text('Отключить вход по бейджу на этом планшете',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }
}
