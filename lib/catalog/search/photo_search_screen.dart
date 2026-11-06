import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:offlinesvet/common/catalog_grid.dart';
import 'package:offlinesvet/catalog/product_list/widgets/product_tile.dart';
import 'package:offlinesvet/catalog/search/photo_region_selector.dart';
import 'package:offlinesvet/catalog/search/photo_search_service.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

/// Поиск товара по фото: менеджер снимает светильник или выбирает снимок
/// из галереи (например, присланный клиентом в WhatsApp), сервер находит
/// похожие товары каталога.
class PhotoSearchScreen extends StatefulWidget {
  const PhotoSearchScreen({super.key, this.initialImageUrl});

  /// «Найти похожие» с карточки товара: искать сразу по этому фото товара.
  final String? initialImageUrl;

  @override
  State<PhotoSearchScreen> createState() => _PhotoSearchScreenState();
}

class _PhotoSearchScreenState extends State<PhotoSearchScreen> {
  static const _green = Color(0xFF4CAF50);
  static const _fullRegion = Rect.fromLTRB(0, 0, 1, 1);
  static const _researchDelay = Duration(milliseconds: 400);

  final _service = PhotoSearchService();
  final _picker = ImagePicker();

  File? _original;            // снимок целиком
  Rect _region = _fullRegion; // выделенная область (доли 0…1)
  File? _photo;               // то, что ушло в поиск (вырезанная область)
  bool _loading = false;      // первый поиск — экран ожидания
  bool _refreshing = false;   // повторный поиск после сдвига рамки — выдача остаётся на месте
  String? _loadingText;
  String? _error;
  PhotoSearchResult? _result;
  bool _feedbackSent = false;
  Timer? _debounce;
  int _seq = 0;               // номер запроса: ответы на устаревшие запросы отбрасываем

  @override
  void initState() {
    super.initState();
    final url = widget.initialImageUrl;
    if (url != null && url.isNotEmpty) _fromUrl(url);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ── откуда фото ───────────────────────────────────────────────────────

  Future<void> _pick(ImageSource source) async {
    final XFile? file;
    try {
      // Уменьшаем фото ещё на телефоне: 1280 px нейросети хватает с запасом,
      // а отправка занимает секунды даже по мобильной связи.
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
    } catch (e) {
      setState(() => _error = source == ImageSource.camera
          ? 'Нет доступа к камере. Разрешите его в настройках телефона.'
          : 'Нет доступа к фото. Разрешите его в настройках телефона.');
      return;
    }
    if (file == null) return; // менеджер передумал
    _startWith(File(file.path));
  }

  /// Фото товара по адресу (кнопка «Найти похожие» на карточке товара).
  Future<void> _fromUrl(String url) async {
    setState(() {
      _loading = true;
      _loadingText = 'Загружаю фото товара…';
      _error = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/similar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Dio().download(url, path,
          options: Options(receiveTimeout: const Duration(seconds: 20)));
      if (!mounted) return;
      _startWith(File(path));
    } catch (e) {
      debugPrint('PhotoSearch: фото товара не загрузилось ($e)');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить фото товара. Проверьте интернет и попробуйте ещё раз.';
      });
    }
  }

  /// Новое фото: сразу ищем по всему снимку, рамку можно двигать потом.
  void _startWith(File file) {
    _original = file;
    _region = _fullRegion;
    _result = null;
    _run(file, firstSearch: true);
  }

  // ── поиск ─────────────────────────────────────────────────────────────

  /// Рамку отпустили — через короткую паузу ищем по новой области.
  void _onRegionChangeEnd(Rect r) {
    _region = r;
    _debounce?.cancel();
    _debounce = Timer(_researchDelay, _searchRegion);
  }

  Future<void> _searchRegion() async {
    final src = _original;
    if (src == null) return;
    File photo;
    try {
      photo = await cropPhotoRegion(src, _region);
    } catch (e) {
      debugPrint('PhotoSearch crop: $e');
      photo = src; // не получилось вырезать — ищем по всему снимку
    }
    if (!mounted) return;
    _run(photo);
  }

  Future<void> _run(File photo, {bool firstSearch = false}) async {
    final seq = ++_seq;
    setState(() {
      _photo = photo;
      _error = null;
      _feedbackSent = false;
      if (firstSearch || _result == null) {
        _loading = true;
        _loadingText = 'Ищу похожие светильники…';
      } else {
        _refreshing = true;
      }
    });
    try {
      final r = await _service.search(photo.path);
      if (!mounted || seq != _seq) return; // пока искали, рамку сдвинули ещё раз
      setState(() {
        _result = r;
        _loading = false;
        _refreshing = false;
      });
    } on PhotoSearchException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      debugPrint('PhotoSearch: $e');
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = 'Не удалось выполнить поиск. Попробуйте ещё раз.';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _reset() {
    _debounce?.cancel();
    _seq++;
    setState(() {
      _original = null;
      _photo = null;
      _result = null;
      _error = null;
      _loading = false;
      _refreshing = false;
    });
  }

  void _sendFeedback(String verdict) {
    final q = _result?.queryId ?? '';
    _service.feedback(q, verdict);
    setState(() => _feedbackSent = true);
  }

  // ── экран ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.initialImageUrl != null ? 'Похожие товары' : 'Поиск по фото'),
      ),
      body: _buildBody(),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.catalog),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_original != null && (_result != null || _error != null)) return _buildWorkspace();
    return _buildPicker();
  }

  Widget _buildPicker() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_camera_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Сфотографируйте светильник или выберите фото из галереи — '
                'например, снимок, который клиент прислал в WhatsApp.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 15),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Сфотографировать', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Colors.black26),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Выбрать из галереи', style: TextStyle(fontSize: 16)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 20),
                _errorBox(_error!),
                if (widget.initialImageUrl != null && _original == null)
                  TextButton(
                    onPressed: () => _fromUrl(widget.initialImageUrl!),
                    child: const Text('Повторить с фото товара'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBECEB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFF9B2C22))),
      );

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_photo!, width: 200, height: 200, fit: BoxFit.cover),
            ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_loadingText ?? 'Ищу похожие светильники…',
              style: const TextStyle(color: Colors.black54, fontSize: 15)),
        ],
      ),
    );
  }

  // ── рабочая область: фото с рамкой + выдача ───────────────────────────
  // Рамку можно двигать сколько угодно раз: после каждого отпускания
  // поиск повторяется по выделенной области, выдача обновляется на месте.
  // На широком экране (планшет горизонтально) фото слева, товары справа;
  // на телефоне — фото сверху, товары листаются под ним.

  Widget _buildWorkspace() {
    final wide = MediaQuery.of(context).size.width >= 900;
    final selector = _buildSelectorPanel(wide);
    final results = _buildResults();
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 340, child: selector),
          Expanded(child: results),
        ],
      );
    }
    final h = MediaQuery.of(context).size.height;
    return Column(
      children: [
        SizedBox(height: (h * 0.32).clamp(180.0, 300.0), child: selector),
        Expanded(child: results),
      ],
    );
  }

  Widget _buildSelectorPanel(bool wide) {
    final photo = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(6),
        child: PhotoRegionSelector(
          image: _original!,
          region: _region,
          onChanged: (r) => setState(() => _region = r),
          onChangeEnd: _onRegionChangeEnd,
        ),
      ),
    );
    final hint = Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text('Двигайте рамку — товары обновятся сами',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          ),
          TextButton(onPressed: _reset, child: const Text('Другое фото')),
        ],
      ),
    );
    if (wide) {
      return Column(
        children: [
          SizedBox(height: (MediaQuery.of(context).size.height * 0.5).clamp(240.0, 420.0), child: photo),
          hint,
        ],
      );
    }
    return Column(children: [Expanded(child: photo), hint]);
  }

  Widget _buildResults() {
    final r = _result;
    final n = r?.products.length ?? 0;
    final columns = catalogColumns(context) - (MediaQuery.of(context).size.width >= 900 ? 1 : 0);
    final whole = _region == _fullRegion;

    final grid = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r != null) ...[
                  Text(
                    n > 0 ? 'Нашлось $n ${_plural(n, 'товар', 'товара', 'товаров')}' : 'Похожих товаров не нашлось',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text('${whole ? 'По всему фото' : 'По выделенной области'} · ${_seconds(r.tookMs)}',
                      style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _errorBox(_error!),
                ],
              ],
            ),
          ),
        ),
        if (n > 0) SliverToBoxAdapter(child: _buildFeedback()),
        if (r != null && n == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Выделите светильник рамкой поточнее или снимите его ближе, целиком и на однотонном фоне.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ),
            ),
          )
        else if (n > 0)
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns < 2 ? 2 : columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.62, // как в обычном поиске
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final p = r!.products[i];
                  final score = r.scores[p.id];
                  return Stack(
                    children: [
                      Positioned.fill(child: ProductTile(product: p)),
                      if (score != null)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${(score * 100).round()}%',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                childCount: n,
              ),
            ),
          ),
      ],
    );

    // Пока идёт повторный поиск — прежняя выдача бледнеет, сверху индикатор
    return Stack(
      children: [
        AnimatedOpacity(
          opacity: _refreshing ? 0.45 : 1,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(ignoring: _refreshing, child: grid),
        ),
        if (_refreshing)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
      ],
    );
  }

  Widget _buildFeedback() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _feedbackSent
          ? const Text('Отметка сохранена. Спасибо!',
              style: TextStyle(color: Color(0xFF2F7D4F), fontSize: 14))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Нужный светильник есть в выдаче?', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 4, child: _chip('Тот самый', 'yes')),
                    const SizedBox(width: 6),
                    Expanded(flex: 5, child: _chip('Похожая модель', 'variant')),
                    const SizedBox(width: 6),
                    Expanded(flex: 3, child: _chip('Нет', 'no')),
                  ],
                ),
              ],
            ),
    );
  }

  /// Кнопка отметки. «Похожая модель» — та же модель другого цвета или размера.
  Widget _chip(String label, String verdict) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          backgroundColor: const Color(0xFFF3F2F7),
          side: const BorderSide(color: Colors.black12),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: () => _sendFeedback(verdict),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  static String _plural(int n, String one, String few, String many) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }

  static String _seconds(int ms) =>
      '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} с';
}
