import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';
import 'package:offlinesvet/repositories/products/models/product.dart';

const String _baseUrl = 'https://prons.kz/ajax/offlinesvet';

/// Сканер штрихкодов — аналог компонента saryal:barcode_scanner на сайте.
/// В отличие от сайта (который декодирует штрихкод в браузере через
/// QuaggaJS), тут декодирование делает нативная библиотека прямо на
/// устройстве (ML Kit) — сервер нужен только для поиска товара по уже
/// распознанному коду, коротким запросом.
///
/// Сейчас поиск по штрихкоду работает только при интернете (как и на
/// сайте) — штрихкод не входит в офлайн-кэш каталога.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _dio = Dio();
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );

  bool _busy = false; // идёт запрос на сервер — игнорируем новые кадры
  String? _lastCode; // защита от повторной обработки одного и того же кадра подряд

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (code == null || code.isEmpty || code == _lastCode) return;

    _lastCode = code;
    setState(() => _busy = true);
    await _controller.stop();

    try {
      final response = await _dio.get(
        '$_baseUrl/get_product_by_barcode.php',
        queryParameters: {'barcode': code},
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data as String) as Map<String, dynamic>;

      if (json['success'] == true) {
        final product = Product.fromJson(json['product'] as Map<String, dynamic>);
        if (!mounted) return;
        await Navigator.of(context).pushNamed('/products-item', arguments: product);
      } else {
        if (!mounted) return;
        _showNotFound(json['error']?.toString() ?? 'Товар со штрихкодом $code не найден');
      }
    } catch (e) {
      if (!mounted) return;
      // Нет интернета или сервер недоступен — поиск по штрихкоду пока
      // работает только онлайн (так же, как на сайте).
      _showNotFound('Нет соединения с сервером. Проверьте интернет и попробуйте снова.');
    } finally {
      if (mounted) setState(() => _busy = false);
      _lastCode = null;
      await _controller.start();
    }
  }

  void _showNotFound(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade600),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Сканер', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Рамка-подсказка, куда наводить камеру
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text('Ищем товар...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0, right: 0, bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Наведите камеру на штрихкод товара',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.scanner),
    );
  }
}
