import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Выбор области на фото: рамка с уголками поверх снимка. Уголки тянут —
/// рамка меняет размер, саму рамку тянут — она переезжает. Область хранится
/// в долях от размера фото (0…1), поэтому не зависит от размера экрана.
class PhotoRegionSelector extends StatefulWidget {
  const PhotoRegionSelector({
    super.key,
    required this.image,
    required this.region,
    required this.onChanged,
  });

  final File image;
  final Rect region;
  final ValueChanged<Rect> onChanged;

  @override
  State<PhotoRegionSelector> createState() => _PhotoRegionSelectorState();
}

enum _Drag { none, move, tl, tr, bl, br }

class _PhotoRegionSelectorState extends State<PhotoRegionSelector> {
  static const _minSide = 0.12; // рамка не меньше 12% снимка по каждой стороне
  static const _handleHit = 32.0; // радиус, в котором палец «берёт» уголок

  Size? _imageSize; // реальный размер фото в пикселях
  _Drag _drag = _Drag.none;
  // Рабочая копия области. Несколько касаний могут прийти до перерисовки,
  // поэтому каждое следующее считаем от неё, а не от устаревшего widget.region.
  late Rect _region = widget.region;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  @override
  void didUpdateWidget(PhotoRegionSelector old) {
    super.didUpdateWidget(old);
    if (old.image.path != widget.image.path) _loadSize();
    if (_drag == _Drag.none) _region = widget.region;
  }

  Future<void> _loadSize() async {
    final bytes = await widget.image.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble()));
    frame.image.dispose();
  }

  /// Где на экране лежит фото при вписывании (как BoxFit.contain).
  Rect _imageRect(Size box) {
    final img = _imageSize!;
    final scale = (box.width / img.width) < (box.height / img.height)
        ? box.width / img.width
        : box.height / img.height;
    final w = img.width * scale, h = img.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Rect _toScreen(Rect r, Rect img) => Rect.fromLTRB(
        img.left + r.left * img.width,
        img.top + r.top * img.height,
        img.left + r.right * img.width,
        img.top + r.bottom * img.height,
      );

  void _onStart(Offset p, Rect sel) {
    final corners = {
      _Drag.tl: sel.topLeft,
      _Drag.tr: sel.topRight,
      _Drag.bl: sel.bottomLeft,
      _Drag.br: sel.bottomRight,
    };
    for (final e in corners.entries) {
      if ((e.value - p).distance <= _handleHit) {
        _drag = e.key;
        return;
      }
    }
    _drag = sel.inflate(8).contains(p) ? _Drag.move : _Drag.none;
  }

  void _onUpdate(Offset delta, Rect img) {
    if (_drag == _Drag.none) return;
    final dx = delta.dx / img.width, dy = delta.dy / img.height;
    var r = _region;
    double cl(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

    switch (_drag) {
      case _Drag.move:
        final mx = cl(dx, -r.left, 1 - r.right);
        final my = cl(dy, -r.top, 1 - r.bottom);
        r = r.shift(Offset(mx, my));
      case _Drag.tl:
        r = Rect.fromLTRB(cl(r.left + dx, 0, r.right - _minSide), cl(r.top + dy, 0, r.bottom - _minSide), r.right, r.bottom);
      case _Drag.tr:
        r = Rect.fromLTRB(r.left, cl(r.top + dy, 0, r.bottom - _minSide), cl(r.right + dx, r.left + _minSide, 1), r.bottom);
      case _Drag.bl:
        r = Rect.fromLTRB(cl(r.left + dx, 0, r.right - _minSide), r.top, r.right, cl(r.bottom + dy, r.top + _minSide, 1));
      case _Drag.br:
        r = Rect.fromLTRB(r.left, r.top, cl(r.right + dx, r.left + _minSide, 1), cl(r.bottom + dy, r.top + _minSide, 1));
      case _Drag.none:
        break;
    }
    _region = r;
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    if (_imageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      final img = _imageRect(box);
      final sel = _toScreen(_region, img);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Считать движение с момента касания: иначе первые ~36 px пути
        // пальца «съедаются» порогом жеста и рамка отстаёт от пальца.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => _onStart(d.localPosition, sel),
        onPanUpdate: (d) => _onUpdate(d.delta, img),
        onPanEnd: (_) => _drag = _Drag.none,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: img,
              child: Image.file(widget.image, fit: BoxFit.fill),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _SelectionPainter(image: img, selection: sel)),
            ),
          ],
        ),
      );
    });
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({required this.image, required this.selection});
  final Rect image;
  final Rect selection;

  @override
  void paint(Canvas canvas, Size size) {
    // Затемнение снимка вне рамки
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(image)
      ..addRect(selection);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.45));

    // Рамка
    canvas.drawRect(
      selection,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );

    // Зелёные уголки
    const len = 22.0;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4CAF50);
    final s = selection;
    for (final c in [
      [s.topLeft, const Offset(len, 0), const Offset(0, len)],
      [s.topRight, const Offset(-len, 0), const Offset(0, len)],
      [s.bottomLeft, const Offset(len, 0), const Offset(0, -len)],
      [s.bottomRight, const Offset(-len, 0), const Offset(0, -len)],
    ]) {
      canvas.drawLine(c[0], c[0] + c[1], p);
      canvas.drawLine(c[0], c[0] + c[2], p);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => old.selection != selection || old.image != image;
}

/// Вырезает область (в долях 0…1) из фото и сохраняет во временный PNG.
/// Если выбрано всё фото, возвращает исходный файл без перекодирования.
Future<File> cropPhotoRegion(File src, Rect region) async {
  const eps = 0.01;
  if (region.left <= eps && region.top <= eps && region.right >= 1 - eps && region.bottom >= 1 - eps) {
    return src;
  }
  final codec = await ui.instantiateImageCodec(await src.readAsBytes());
  final image = (await codec.getNextFrame()).image;
  final w = image.width.toDouble(), h = image.height.toDouble();
  final from = Rect.fromLTRB(region.left * w, region.top * h, region.right * w, region.bottom * h);
  final outW = from.width.round().clamp(1, 4096), outH = from.height.round().clamp(1, 4096);

  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(
    image,
    from,
    Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final out = await rec.endRecording().toImage(outW, outH);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  out.dispose();

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/photo_search_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  return file;
}
