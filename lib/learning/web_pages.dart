import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:offlinesvet/learning/advice_html.dart';
import 'package:offlinesvet/learning/learning_data.dart';

const _green = Color(0xFF4CAF50);
const _bg = Color(0xFFF3F2F7);

PreferredSizeWidget _bar(String title) => AppBar(
      backgroundColor: _green,
      foregroundColor: Colors.white,
      centerTitle: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    );

/// Страница в WebView: HTML-строка или адрес. Переходы на другие сайты
/// не открываются внутри (для отчётов Power BI — разрешены).
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.title, this.html, this.url, this.allowAnyHost = false, this.landscapeHint = false});
  final String title;
  final String? html;
  final String? url;
  final bool allowAnyHost;
  final bool landscapeHint;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
        onNavigationRequest: (r) {
          if (widget.allowAnyHost) return NavigationDecision.navigate;
          final u = Uri.tryParse(r.url);
          if (u == null) return NavigationDecision.prevent;
          if (u.scheme == 'about' || u.scheme == 'data' || u.fragment.isNotEmpty && r.url.startsWith('https://offline.svet.kz/advice')) {
            return NavigationDecision.navigate;
          }
          return r.isMainFrame && widget.html != null ? NavigationDecision.prevent : NavigationDecision.navigate;
        },
      ));
    if (widget.html != null) {
      _c.loadHtmlString(widget.html!, baseUrl: 'https://offline.svet.kz/advice/');
    } else {
      _c.loadRequest(Uri.parse(widget.url!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _bar(widget.title),
      body: Stack(children: [
        WebViewWidget(controller: _c),
        if (_loading) const LinearProgressIndicator(color: _green, backgroundColor: Color(0xFFE8F5E9)),
      ]),
    );
  }
}

/// «Обучение» — видеоуроки со страницы /obuchenie_svet/ сайта и кнопка
/// «Советы для новых менеджеров».
class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Обучение'),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF212121),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdviceScreen())),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Советы для новых менеджеров', style: TextStyle(fontSize: 15)),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(learningVideos.length, (i) {
          final v = learningVideos[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE8F5E9),
                child: Text('${i + 1}', style: const TextStyle(color: _green, fontWeight: FontWeight.w700)),
              ),
              title: Text(v.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.play_circle_fill, color: _green, size: 30),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(video: v))),
            ),
          );
        }),
      ]),
    );
  }
}

/// Просмотр видеоурока — встроенный плеер (HTML5 video), с полноэкранным режимом.
class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key, required this.video});
  final LearningVideo video;

  @override
  Widget build(BuildContext context) {
    final html = '''<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{margin:0;background:#000;display:flex;align-items:center;justify-content:center;height:100vh}
video{width:100%;max-height:100vh}</style></head><body>
<video controls autoplay playsinline src="${video.url}"></video></body></html>''';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _bar(video.title),
      body: _HtmlView(html: html),
    );
  }
}

class _HtmlView extends StatefulWidget {
  const _HtmlView({required this.html});
  final String html;
  @override
  State<_HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<_HtmlView> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..loadHtmlString(widget.html, baseUrl: 'https://offline.svet.kz/');
  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}

/// «Советы для новых менеджеров» — текст и картинки страницы /advice/ сайта.
class AdviceScreen extends StatelessWidget {
  const AdviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const page = '''<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 body{margin:0;padding:14px;font-family:-apple-system,Roboto,sans-serif;color:#222;line-height:1.5;background:#fff}
 h2{font-size:20px;margin:6px 0 10px} h3{font-size:17px;margin:18px 0 8px}
 .bold{font-weight:700} img{max-width:100%;height:auto;border-radius:8px;margin:8px 0;box-shadow:0 1px 6px rgba(0,0,0,.12)}
 a{color:#2E7D32} .adviсe-block-content-link a{display:block;padding:4px 0}
 ul{padding-left:20px}
</style></head><body>$adviceHtml</body></html>''';
    return const WebPageScreen(title: 'Советы', html: page);
  }
}

/// «Графики» — отчёты Power BI со страницы /managers_reports/grafiki.php.
class ChartsScreen extends StatelessWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _bar('Графики'),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Отчёты удобнее смотреть, повернув телефон горизонтально.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
        ...chartReports.map((r) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.bar_chart_rounded, color: _green, size: 30),
                title: Text(r.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: r.needsLogin
                    ? const Text('Нужен вход в учётную запись Microsoft', style: TextStyle(fontSize: 12))
                    : null,
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => WebPageScreen(title: r.title, url: r.url, allowAnyHost: true))),
              ),
            )),
      ]),
    );
  }
}
