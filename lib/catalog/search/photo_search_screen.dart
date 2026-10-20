import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:offlinesvet/catalog/product_list/widgets/product_tile.dart';
import 'package:offlinesvet/catalog/search/photo_region_selector.dart';
import 'package:offlinesvet/catalog/search/photo_search_service.dart';
import 'package:offlinesvet/common/bottom_nav/app_bottom_nav_bar.dart';

/// Поиск товара по фото: менеджер снимает светильник или выбирает снимок
/// из галереи (например, присланный клиентом в WhatsApp), сервер находит
/// похожие товары каталога.
class PhotoSearchScreen extends StatefulWidget {
  const PhotoSearchScreen({super.key});

  @override
  State<PhotoSearchScreen> createState() => _PhotoSearchScreenState();
}

class _PhotoSearchScreenState extends State<PhotoSearchScreen> {
  static const _green = Color(0xFF4CAF50);

  final _service = PhotoSearchService();
  final _picker = ImagePicker();

  static const _fullRegion = Rect.fromLTRB(0, 0, 1, 1);

  File? _original;            // снимок целиком, как его выбрал менеджер
  Rect _region = _fullRegion; // выделенная область (доли 0…1)
  bool _editing = false;      // открыт выбор области
  File? _photo;               // то, что ушло в поиск (вырезанная область)
  bool _loading = false;
  String? _error;
  PhotoSearchResult? _result;
  bool _feedbackSent = false;

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
    setState(() {
      _original = File(file!.path);
      _region = _fullRegion;
      _editing = true;
      _error = null;
      _result = null;
    });
  }

  /// Вырезает выделенную область и ищет по ней.
  Future<void> _searchRegion() async {
    final src = _original;
    if (src == null) return;
    setState(() {
      _editing = false;
      _loading = true;
      _photo = src;
    });
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

  Future<void> _run(File photo) async {
    setState(() {
      _photo = photo;
      _loading = true;
      _error = null;
      _result = null;
      _feedbackSent = false;
    });
    try {
      final r = await _service.search(photo.path);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } on PhotoSearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      debugPrint('PhotoSearch: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось выполнить поиск. Попробуйте ещё раз.';
        _loading = false;
      });
    }
  }

  void _reset() => setState(() {
        _original = null;
        _photo = null;
        _result = null;
        _error = null;
        _editing = false;
      });

  void _sendFeedback(String verdict) {
    final q = _result?.queryId ?? '';
    _service.feedback(q, verdict);
    setState(() => _feedbackSent = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Поиск по фото'),
      ),
      body: _buildBody(),
      bottomNavigationBar: const AppBottomNavBar(currentTab: AppBottomTab.catalog),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_editing && _original != null) return _buildEditor();
    if (_result != null) return _buildResults(_result!);
    return _buildPicker();
  }

  // ── выбор фото ────────────────────────────────────────────────────────

  Widget _buildPicker() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBECEB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: const TextStyle(color: Color(0xFF9B2C22))),
              ),
              if (_photo != null)
                TextButton(
                  onPressed: () => _run(_photo!),
                  child: const Text('Повторить с этим фото'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── выбор области ─────────────────────────────────────────────────────

  Widget _buildEditor() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Выделите светильник рамкой — потяните за зелёные уголки. '
            'Так поиск будет точнее.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: PhotoRegionSelector(
              image: _original!,
              region: _region,
              onChanged: (r) => setState(() => _region = r),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.black26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _reset,
                    child: const Text('Другое фото', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _searchRegion,
                    icon: const Icon(Icons.search),
                    label: const Text('Найти', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── ожидание ──────────────────────────────────────────────────────────

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
          const Text('Ищу похожие светильники…',
              style: TextStyle(color: Colors.black54, fontSize: 15)),
        ],
      ),
    );
  }

  // ── выдача ────────────────────────────────────────────────────────────

  Widget _buildResults(PhotoSearchResult r) {
    final n = r.products.length;
    final columns = MediaQuery.of(context).size.width >= 576 ? 3 : 2;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                if (_photo != null)
                  GestureDetector(
                    // Нажатие на миниатюру — поправить область и искать заново
                    onTap: _original == null ? null : () => setState(() => _editing = true),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_photo!, width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        if (_original != null)
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.crop, size: 14, color: _green),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n > 0 ? 'Нашлось $n ${_plural(n, 'товар', 'товара', 'товаров')}' : 'Похожих товаров не нашлось',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text('Поиск занял ${_seconds(r.tookMs)}',
                          style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Colors.black26),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _reset,
                  child: const Text('Другое фото'),
                ),
              ],
            ),
          ),
        ),
        if (n > 0) SliverToBoxAdapter(child: _buildFeedback()),
        if (n == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Попробуйте снять светильник ближе, целиком и на однотонном фоне.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.62, // как в обычном поиске
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final p = r.products[i];
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
