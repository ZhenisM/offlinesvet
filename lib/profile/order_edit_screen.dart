import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  String _login = '';
  String _password = '';

  static const _baseHost = 'prons.kz';
  static const _editPath = '/bitrix/admin/sale_order_edit.php';
  static const _adminLoginUrl = 'https://prons.kz/bitrix/admin/index.php';

  String get _editUrl =>
      'https://$_baseHost$_editPath?ID=${widget.orderId}&lang=ru&IFRAME=Y';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final prefs = await SharedPreferences.getInstance();
    _login    = prefs.getString('bitrix_login') ?? '';
    _password = prefs.getString('bitrix_password') ?? '';

    if (_login.isEmpty || _password.isEmpty) {
      setState(() {
        _error = 'Войдите в приложение заново чтобы открыть редактор.';
        _loading = false;
      });
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _loading = false);

          // Если это страница логина Bitrix-админки — заполняем и сабмитим форму
          if (url.contains('/bitrix/admin/index.php') ||
              url.contains('AUTH_FORM') ||
              url == _adminLoginUrl) {
            final safeLogin    = _login.replaceAll("'", "\\'");
            final safePassword = _password.replaceAll("'", "\\'");
            final editUrl      = _editUrl;
            _controller.runJavaScript('''
              (function() {
                var loginField = document.querySelector('input[name="USER_LOGIN"]');
                var passField  = document.querySelector('input[name="USER_PASSWORD"]');
                var form       = document.querySelector('form');
                
                if (loginField && passField && form) {
                  loginField.value = '$safeLogin';
                  passField.value  = '$safePassword';
                  
                  // Добавляем backurl чтобы после логина попасть на редактор
                  var backurl = document.querySelector('input[name="backurl"]');
                  if (!backurl) {
                    backurl = document.createElement('input');
                    backurl.type = 'hidden';
                    backurl.name = 'backurl';
                    form.appendChild(backurl);
                  }
                  backurl.value = '$editUrl';
                  
                  // Устанавливаем тип авторизации
                  var authForm = document.querySelector('input[name="AUTH_FORM"]');
                  if (!authForm) {
                    authForm = document.createElement('input');
                    authForm.type = 'hidden';
                    authForm.name = 'AUTH_FORM';
                    authForm.value = 'Y';
                    form.appendChild(authForm);
                  }
                  var typeField = document.querySelector('input[name="TYPE"]');
                  if (!typeField) {
                    typeField = document.createElement('input');
                    typeField.type = 'hidden';
                    typeField.name = 'TYPE';
                    typeField.value = 'AUTH';
                    form.appendChild(typeField);
                  }
                  
                  form.submit();
                }
              })();
            ''');
          }

          // Если авторизация прошла и мы в админке — переходим на редактор
          if (url.contains('/bitrix/admin/') &&
              !url.contains('AUTH_FORM') &&
              !url.contains('index.php') &&
              !url.contains(_editPath)) {
            _controller.loadRequest(Uri.parse(_editUrl));
            return;
          }

          // Если уже на странице index.php но без формы логина — значит залогинены
          if (url.contains('/bitrix/admin/index.php')) {
            _controller.runJavaScript('''
              if (!document.querySelector('input[name="USER_LOGIN"]')) {
                window.location.href = '${_editUrl.replaceAll("'", "\'")}';
              }
            ''');
          }

          // На любой другой странице — скрываем элементы Bitrix-админки
          _controller.runJavaScript('''
            var header = document.getElementById('header');
            if (header) header.style.display = 'none';
            var leftPanel = document.getElementById('bx-panel');
            if (leftPanel) leftPanel.style.display = 'none';
            var workzone = document.getElementById('workarea-content');
            if (workzone) workzone.style.marginLeft = '0';
            var btnList = document.getElementById('btn_list');
            if (btnList) btnList.style.display = 'none';
          ''');
        },
        onWebResourceError: (error) {
          if (mounted && error.errorType == WebResourceErrorType.hostLookup) {
            setState(() => _error = 'Нет подключения к интернету');
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.host == _baseHost) return NavigationDecision.navigate;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Заказ сохранён')));
            Navigator.of(context).pop(true);
          }
          return NavigationDecision.prevent;
        },
      ));

    setState(() => _cookiesReady = true);

    // Открываем страницу логина Bitrix-админки
    // onPageFinished автоматически заполнит форму и отправит её
    await _controller.loadRequest(Uri.parse(_adminLoginUrl));
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
