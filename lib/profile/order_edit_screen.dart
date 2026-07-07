import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Экран редактирования заказа через Bitrix-админку на prons.kz.
/// Открывает /bitrix/admin/sale_order_edit.php в WebView с куками сессии.
class OrderEditScreen extends StatefulWidget {
  final int orderId;
  final String orderNumber;

  const OrderEditScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _cookiesReady = false;
  String? _error;

  static const _baseHost = 'prons.kz';
  static const _editPath = '/bitrix/admin/sale_order_edit.php';

  String get _editUrl =>
      'https://$_baseHost$_editPath?ID=${widget.orderId}&lang=ru&IFRAME=Y';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final prefs  = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    final token  = prefs.getString('auth_token') ?? '';

    // Формируем URL через webview_login.php — он авторизует и редиректит
    final redirectPath = Uri.encodeComponent(
      '/bitrix/admin/sale_order_edit.php'
      '?ID=${widget.orderId}&lang=ru&IFRAME=Y',
    );
    final startUrl = userId.isNotEmpty
        ? 'https://$_baseHost/ajax/offlinesvet/webview_login.php'
          '?user_id=${Uri.encodeComponent(userId)}'
          '&token=${Uri.encodeComponent(token)}'
          '&redirect=$redirectPath'
        : _editUrl;

    // Инициализируем WebView
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (url) {
          setState(() => _loading = false);
          // Скрываем лишние элементы Bitrix-админки (шапка, меню)
          _controller.runJavaScript('''
            // Скрываем верхнее меню и левую панель Bitrix
            var header = document.getElementById('header');
            if (header) header.style.display = 'none';
            var leftPanel = document.getElementById('bx-panel');
            if (leftPanel) leftPanel.style.display = 'none';
            var workzone = document.getElementById('workarea-content');
            if (workzone) workzone.style.marginLeft = '0';
            // Кнопка "Список" в Bitrix-админке — скрываем
            var btnList = document.getElementById('btn_list');
            if (btnList) btnList.style.display = 'none';
          ''');
        },
        onWebResourceError: (error) {
          if (mounted) setState(() => _error = error.description);
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;

          // Разрешаем только страницы редактирования заказа на prons.kz
          final allowed = [
            '/bitrix/admin/sale_order_edit.php',
            '/bitrix/admin/sale_order_shipment_edit.php',
          ];
          final isAllowed = uri.host == _baseHost &&
              allowed.any((p) => uri.path.startsWith(p));

          if (!isAllowed) {
            // Переход на другую страницу — закрываем WebView как на сайте
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Заказ сохранён')));
              Navigator.of(context).pop(true); // true = заказ изменён
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));

    setState(() => _cookiesReady = true);

    // Загружаем через webview_login.php — он авторизует и редиректит на редактор
    await _controller.loadRequest(Uri.parse(startUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text('Заказ #${widget.orderNumber}'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cookiesReady
                ? () => _controller.loadRequest(Uri.parse(_editUrl))
                : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            setState(() { _error = null; _loading = true; });
            _initWebView();
          },
          child: const Text('Повторить'),
        ),
      ]));
    }

    if (!_cookiesReady) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Color(0xFF4CAF50)),
        SizedBox(height: 12),
        Text('Открываем редактор...'),
      ]));
    }

    return Stack(children: [
      WebViewWidget(controller: _controller),
      if (_loading)
        const LinearProgressIndicator(
          color: Color(0xFF4CAF50),
          backgroundColor: Color(0xFFE8F5E9),
        ),
    ]);
  }
}
