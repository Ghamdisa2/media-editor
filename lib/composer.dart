import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'common.dart';
import 'strings.dart';

enum LKind { text, image, icon, shape }

const fonts = <(String, String, String)>[
  ('Tajawal', 'تجوال', 'Tajawal'),
  ('Amiri', 'أميري', 'Amiri'),
  ('ReemKufi', 'ريم كوفي', 'Reem Kufi'),
  ('Lemonada', 'ليمونادا', 'Lemonada'),
  ('Marhey', 'مرحي', 'Marhey'),
  ('Pacifico', 'Pacifico', 'Pacifico'),
  ('Lobster', 'Lobster', 'Lobster'),
  ('BebasNeue', 'Bebas', 'Bebas'),
  ('Anton', 'Anton', 'Anton'),
];

const iconList = <IconData>[
  Icons.star, Icons.favorite, Icons.bolt, Icons.camera_alt, Icons.music_note,
  Icons.movie, Icons.videocam, Icons.mic, Icons.headphones, Icons.public,
  Icons.rocket_launch, Icons.diamond, Icons.shield, Icons.verified, Icons.local_fire_department,
  Icons.eco, Icons.pets, Icons.coffee, Icons.restaurant, Icons.shopping_bag,
  Icons.sports_soccer, Icons.fitness_center, Icons.palette, Icons.brush, Icons.code,
  Icons.cloud, Icons.light_mode, Icons.nightlight, Icons.anchor, Icons.flight,
  Icons.home, Icons.school, Icons.work, Icons.build, Icons.lock,
  Icons.thumb_up, Icons.emoji_events, Icons.auto_awesome, Icons.waves, Icons.science,
];

class Layer {
  LKind kind;
  String text;
  String font;
  Color color;
  Color? color2; // gradient end (shapes)
  Color outlineColor;
  double size; // fraction of base width
  double rot;
  double opacity;
  double dx, dy; // centre, 0..1
  bool bold, outline, shadow, tile;
  double aspect; // height / width for image + shape
  int shape; // 0 rect 1 rounded 2 ellipse 3 hexagon
  IconData? icon;
  Uint8List? bytes;
  ui.Image? img;
  Layer(this.kind,
      {this.text = '',
      this.font = 'Tajawal',
      this.color = Colors.white,
      this.color2,
      this.outlineColor = Colors.black,
      this.size = 0.1,
      this.rot = 0,
      this.opacity = 1,
      this.dx = 0.5,
      this.dy = 0.5,
      this.bold = true,
      this.outline = false,
      this.shadow = true,
      this.tile = false,
      this.aspect = 1,
      this.shape = 1,
      this.icon,
      this.bytes,
      this.img});
}

class ComposerController extends ChangeNotifier {
  final layers = <Layer>[];
  int sel = -1;
  Layer? get cur => sel >= 0 && sel < layers.length ? layers[sel] : null;
  void add(Layer l) {
    layers.add(l);
    sel = layers.length - 1;
    notifyListeners();
  }

  void select(int i) {
    sel = i;
    notifyListeners();
  }

  void removeSel() {
    if (cur == null) return;
    layers.removeAt(sel);
    sel = layers.isEmpty ? -1 : math.min(sel, layers.length - 1);
    notifyListeners();
  }

  void changed() => notifyListeners();
}

bool _isAr(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

TextPainter _textPainter(Layer l, double w, {bool stroke = false}) {
  final base = TextStyle(
    fontFamily: l.font,
    fontSize: l.size * w,
    fontWeight: l.bold ? FontWeight.w700 : FontWeight.w400,
    height: 1.2,
  );
  final alpha = (l.opacity * 255).round();
  final style = stroke
      ? base.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, l.size * w * 0.12)
            ..strokeJoin = StrokeJoin.round
            ..color = l.outlineColor.withAlpha(alpha))
      : base.copyWith(
          color: l.color.withAlpha(alpha),
          shadows: l.shadow
              ? [Shadow(blurRadius: l.size * w * 0.12, offset: Offset(0, l.size * w * 0.04), color: const Color(0x99000000))]
              : null);
  return TextPainter(
    text: TextSpan(text: l.text.isEmpty ? ' ' : l.text, style: style),
    textAlign: TextAlign.center,
    textDirection: _isAr(l.text) ? TextDirection.rtl : TextDirection.ltr,
  )..layout(maxWidth: w * 0.95);
}

Size itemSize(Layer l, double w) {
  switch (l.kind) {
    case LKind.text:
      final tp = _textPainter(l, w);
      return Size(tp.width, tp.height);
    case LKind.icon:
      return Size(l.size * w, l.size * w);
    case LKind.image:
    case LKind.shape:
      return Size(l.size * w, l.size * w * l.aspect);
  }
}

Path _hexagon(Rect r) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = math.pi / 3 * i - math.pi / 2;
    final o = Offset(r.center.dx + r.width / 2 * math.cos(a), r.center.dy + r.height / 2 * math.sin(a));
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

void _drawItem(Canvas c, Layer l, double w) {
  final alpha = (l.opacity * 255).round();
  switch (l.kind) {
    case LKind.text:
      if (l.outline) {
        final s = _textPainter(l, w, stroke: true);
        s.paint(c, Offset(-s.width / 2, -s.height / 2));
      }
      final tp = _textPainter(l, w);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    case LKind.icon:
      final ic = l.icon ?? Icons.star;
      final tp = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(ic.codePoint),
            style: TextStyle(
                fontFamily: ic.fontFamily,
                package: ic.fontPackage,
                fontSize: l.size * w,
                color: l.color.withAlpha(alpha))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    case LKind.image:
      final im = l.img;
      if (im == null) return;
      final s = itemSize(l, w);
      c.drawImageRect(
          im,
          Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
          Rect.fromCenter(center: Offset.zero, width: s.width, height: s.height),
          Paint()
            ..color = Color.fromARGB(alpha, 255, 255, 255)
            ..filterQuality = FilterQuality.high);
    case LKind.shape:
      final s = itemSize(l, w);
      final r = Rect.fromCenter(center: Offset.zero, width: s.width, height: s.height);
      final p = Paint()..color = l.color.withAlpha(alpha);
      if (l.color2 != null) {
        p.shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [l.color.withAlpha(alpha), l.color2!.withAlpha(alpha)])
            .createShader(r);
      }
      switch (l.shape) {
        case 0:
          c.drawRect(r, p);
        case 1:
          c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide * 0.22)), p);
        case 2:
          c.drawOval(r, p);
        default:
          c.drawPath(_hexagon(r), p);
      }
  }
}

void paintLayer(Canvas c, Layer l, double w, double h) {
  c.save();
  if (l.tile) {
    c.translate(w / 2, h / 2);
    c.rotate(l.rot);
    final s = itemSize(l, w);
    final sx = s.width * 1.7 + w * 0.04, sy = s.height * 2.6 + h * 0.04;
    final span = math.sqrt(w * w + h * h);
    for (var y = -span; y < span; y += sy) {
      for (var x = -span; x < span; x += sx) {
        c.save();
        c.translate(x, y);
        _drawItem(c, l, w);
        c.restore();
      }
    }
  } else {
    c.translate(l.dx * w, l.dy * h);
    c.rotate(l.rot);
    _drawItem(c, l, w);
  }
  c.restore();
}

Future<ui.Image> decodeUi(Uint8List b) async =>
    (await (await ui.instantiateImageCodec(b)).getNextFrame()).image;

/// Draw [base] (optional) plus all layers into a PNG of size w x h.
Future<Uint8List> renderLayers(ComposerController cc, int w, int h,
    {Uint8List? base, Color? bg}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  if (base != null) {
    final im = await decodeUi(base);
    c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..filterQuality = FilterQuality.high);
  } else if (bg != null) {
    c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = bg);
  }
  for (final l in cc.layers) {
    paintLayer(c, l, w.toDouble(), h.toDouble());
  }
  final img = await rec.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

class _LayersPainter extends CustomPainter {
  final ComposerController cc;
  _LayersPainter(this.cc) : super(repaint: cc);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < cc.layers.length; i++) {
      final l = cc.layers[i];
      paintLayer(canvas, l, size.width, size.height);
      if (i == cc.sel && !l.tile) {
        final s = itemSize(l, size.width);
        canvas.save();
        canvas.translate(l.dx * size.width, l.dy * size.height);
        canvas.rotate(l.rot);
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: s.width + 10, height: s.height + 10),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = const Color(0xFF00BCD4));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LayersPainter old) => true;
}

class _Checker extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 14.0;
    final a = Paint()..color = const Color(0xFFE8ECEE), b = Paint()..color = const Color(0xFFD3D9DC);
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = 0.0; x < size.width; x += s) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), ((x ~/ s + y ~/ s) % 2 == 0) ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Interactive canvas: drag to move, pinch (or mouse wheel) to scale, two
/// fingers to rotate.
class ComposerCanvas extends StatefulWidget {
  final ComposerController cc;
  final Widget? base;
  final double aspect;
  final bool checker;
  const ComposerCanvas({super.key, required this.cc, required this.aspect, this.base, this.checker = false});
  @override
  State<ComposerCanvas> createState() => _ComposerCanvasState();
}

class _ComposerCanvasState extends State<ComposerCanvas> {
  double s0 = 0.1, r0 = 0;

  int _hit(Offset p, Size sz) {
    for (var i = widget.cc.layers.length - 1; i >= 0; i--) {
      final l = widget.cc.layers[i];
      if (l.tile) continue;
      final s = itemSize(l, sz.width);
      final d = p - Offset(l.dx * sz.width, l.dy * sz.height);
      final rad = math.max(s.width, s.height) / 2 + 12;
      if (d.distance <= rad) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final cc = widget.cc;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: widget.aspect,
        child: LayoutBuilder(builder: (_, cons) {
          final size = Size(cons.maxWidth, cons.maxHeight);
          return Stack(children: [
            Positioned.fill(
                child: widget.base ??
                    (widget.checker
                        ? CustomPaint(painter: _Checker())
                        : Container(color: const Color(0xFF1B2328)))),
            Positioned.fill(
              child: Listener(
                onPointerSignal: (e) {
                  final l = cc.cur;
                  if (e is PointerScrollEvent && l != null) {
                    l.size = (l.size * (e.scrollDelta.dy > 0 ? 0.94 : 1.06)).clamp(0.02, 1.5).toDouble();
                    cc.changed();
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (d) {
                    final i = _hit(d.localFocalPoint, size);
                    if (i >= 0) cc.select(i);
                    s0 = cc.cur?.size ?? 0.1;
                    r0 = cc.cur?.rot ?? 0;
                  },
                  onScaleUpdate: (d) {
                    final l = cc.cur;
                    if (l == null) return;
                    if (!l.tile) {
                      l.dx = (l.dx + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0).toDouble();
                      l.dy = (l.dy + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0).toDouble();
                    }
                    if (d.pointerCount >= 2) {
                      l.size = (s0 * d.scale).clamp(0.02, 1.5).toDouble();
                      l.rot = r0 + d.rotation;
                    }
                    cc.changed();
                  },
                  child: CustomPaint(painter: _LayersPainter(cc), size: Size.infinite),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

/// Add / edit layers.
class ComposerPanel extends StatelessWidget {
  final ComposerController cc;
  final Set<LKind> kinds;
  final bool tileOption;
  const ComposerPanel({super.key, required this.cc, this.kinds = const {LKind.text, LKind.image}, this.tileOption = false});

  Future<void> _addImage(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final b = r?.files.single.bytes;
    if (b == null) return;
    final im = await decodeUi(b);
    cc.add(Layer(LKind.image, bytes: b, img: im, size: 0.25, aspect: im.height / im.width));
  }

  void _addIcon(BuildContext context) {
    showModalBottomSheet(
        context: context,
        builder: (_) => GridView.count(
              crossAxisCount: 8,
              padding: const EdgeInsets.all(16),
              children: [
                for (final ic in iconList)
                  IconButton(
                      icon: Icon(ic),
                      onPressed: () {
                        cc.add(Layer(LKind.icon, icon: ic, size: 0.2, color: Colors.white));
                        Navigator.pop(context);
                      })
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cc,
      builder: (context, _) {
        final l = cc.cur;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(
            title: t(context, 'العناصر', 'Layers'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (kinds.contains(LKind.text))
                  ActionChip(
                      avatar: const Icon(Icons.text_fields, size: 18),
                      label: Text(t(context, 'نص', 'Text')),
                      onPressed: () => cc.add(Layer(LKind.text, text: t(context, 'اكتب هنا', 'Your text'), size: 0.09))),
                if (kinds.contains(LKind.image))
                  ActionChip(
                      avatar: const Icon(Icons.image_outlined, size: 18),
                      label: Text(t(context, 'صورة / شعار', 'Image / logo')),
                      onPressed: () => _addImage(context)),
                if (kinds.contains(LKind.icon))
                  ActionChip(
                      avatar: const Icon(Icons.emoji_symbols, size: 18),
                      label: Text(t(context, 'أيقونة', 'Icon')),
                      onPressed: () => _addIcon(context)),
                if (kinds.contains(LKind.shape))
                  ActionChip(
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: Text(t(context, 'شكل', 'Shape')),
                      onPressed: () => cc.add(Layer(LKind.shape, color: const Color(0xFF0E7C86), color2: const Color(0xFF3B82F6), size: 0.6))),
              ]),
              if (cc.layers.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < cc.layers.length; i++)
                    InputChip(
                      label: Text(switch (cc.layers[i].kind) {
                        LKind.text => cc.layers[i].text.isEmpty ? '…' : cc.layers[i].text,
                        LKind.image => t(context, 'صورة', 'Image'),
                        LKind.icon => t(context, 'أيقونة', 'Icon'),
                        LKind.shape => t(context, 'شكل', 'Shape'),
                      }, overflow: TextOverflow.ellipsis),
                      selected: cc.sel == i,
                      onPressed: () => cc.select(i),
                      onDeleted: () {
                        cc.select(i);
                        cc.removeSel();
                      },
                    ),
                ]),
              ],
            ]),
          ),
          if (l != null) _props(context, l),
        ]);
      },
    );
  }

  Widget _props(BuildContext context, Layer l) {
    return Panel(
      title: t(context, 'خصائص العنصر', 'Properties'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (l.kind == LKind.text) ...[
          TextFormField(
              key: ValueKey(l.hashCode),
              initialValue: l.text,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: t(context, 'النص', 'Text')),
              onChanged: (v) {
                l.text = v;
                cc.changed();
              }),
          const SizedBox(height: 10),
          Text(t(context, 'الخط', 'Font')),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in fonts)
              ChoiceChip(
                  label: Text(t(context, f.$2, f.$3), style: TextStyle(fontFamily: f.$1)),
                  selected: l.font == f.$1,
                  onSelected: (_) {
                    l.font = f.$1;
                    cc.changed();
                  }),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            FilterChip(label: Text(t(context, 'عريض', 'Bold')), selected: l.bold, onSelected: (v) { l.bold = v; cc.changed(); }),
            FilterChip(label: Text(t(context, 'ظل', 'Shadow')), selected: l.shadow, onSelected: (v) { l.shadow = v; cc.changed(); }),
            FilterChip(label: Text(t(context, 'حدود', 'Outline')), selected: l.outline, onSelected: (v) { l.outline = v; cc.changed(); }),
          ]),
        ],
        if (l.kind == LKind.shape) ...[
          Segs(
              items: [('مستطيل', 'Rectangle'), ('مدوّر', 'Rounded'), ('دائرة', 'Ellipse'), ('سداسي', 'Hexagon')],
              sel: l.shape,
              onChanged: (i) { l.shape = i; cc.changed(); }),
          Sld(t(context, 'النسبة (الارتفاع/العرض)', 'Aspect (h/w)'), l.aspect, 0.2, 2, (v) { l.aspect = v; cc.changed(); }),
          Text(t(context, 'لون النهاية (تدرج)', 'Gradient end color')),
          ColorPick(color: l.color2 ?? l.color, onChanged: (c) { l.color2 = c; cc.changed(); }),
        ],
        if (l.kind != LKind.image) ...[
          const SizedBox(height: 8),
          Text(l.kind == LKind.shape ? t(context, 'لون البداية', 'Start color') : t(context, 'اللون', 'Color')),
          ColorPick(color: l.color, onChanged: (c) { l.color = c; cc.changed(); }),
        ],
        if (l.kind == LKind.text && l.outline) ...[
          const SizedBox(height: 8),
          Text(t(context, 'لون الحدود', 'Outline color')),
          ColorPick(color: l.outlineColor, onChanged: (c) { l.outlineColor = c; cc.changed(); }),
        ],
        Sld(t(context, 'الحجم', 'Size'), l.size, 0.02, 1.2, (v) { l.size = v; cc.changed(); }),
        Sld(t(context, 'التدوير', 'Rotation'), l.rot * 180 / math.pi, -180, 180, (v) { l.rot = v * math.pi / 180; cc.changed(); }, fmt: (v) => '${v.round()}°'),
        Sld(t(context, 'الشفافية', 'Opacity'), l.opacity, 0.05, 1, (v) { l.opacity = v; cc.changed(); }),
        if (tileOption)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'تكرار على كامل الصورة', 'Tile across image')),
              value: l.tile,
              onChanged: (v) { l.tile = v; cc.changed(); }),
        if (!l.tile)
          Wrap(spacing: 6, children: [
            for (final p in const [(0.12, 0.12), (0.88, 0.12), (0.5, 0.5), (0.12, 0.88), (0.88, 0.88)])
              OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  onPressed: () { l.dx = p.$1; l.dy = p.$2; cc.changed(); },
                  child: Icon(p == const (0.5, 0.5) ? Icons.center_focus_strong : Icons.north_west, size: 16)),
          ]),
      ]),
    );
  }
}
