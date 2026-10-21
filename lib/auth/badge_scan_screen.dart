import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:offlinesvet/auth/badge_api.dart';

/// Сканер QR-бейджа. Возвращает текст бейджа (OSVB:…) или null.
class BadgeScanScreen extends StatefulWidget {
  const BadgeScanScreen({super.key});

  @override
  State<BadgeScanScreen> createState() => _BadgeScanScreenState();
}

class _BadgeScanScreenState extends State<BadgeScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  DateTime? _hintUntil; // чтобы подсказка «это не бейдж» не мигала на каждом кадре

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (BadgeApi.looksLikeBadge(raw)) {
        _done = true;
        Navigator.of(context).pop(raw!.trim());
        return;
      }
    }
    final now = DateTime.now();
    if (capture.barcodes.isNotEmpty && (_hintUntil == null || now.isAfter(_hintUntil!))) {
      _hintUntil = now.add(const Duration(seconds: 3));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Это не QR-код бейджа'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.of(context).size.shortestSide * 0.65;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Вход по бейджу'),
        actions: [
          IconButton(
            tooltip: 'Другая камера',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF4CAF50), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Наведите камеру на QR-код бейджа',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
