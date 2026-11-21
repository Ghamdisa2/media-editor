import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'strings.dart';

const palette = <Color>[
  Colors.white, Colors.black, Color(0xFFFFD60A), Color(0xFFFF9500),
  Color(0xFFFF3B30), Color(0xFFFF2D55), Color(0xFFAF52DE), Color(0xFF5856D6),
  Color(0xFF007AFF), Color(0xFF5AC8FA), Color(0xFF0E7C86), Color(0xFF34C759),
  Color(0xFFA2845E), Color(0xFF8E8E93), Color(0xFF3A3A3C), Color(0xFFFFCC80),
];

List<String> get fontList => Platform.isWindows
    ? ['Arial', 'Tahoma', 'Segoe UI', 'Times New Roman', 'Courier New', 'Impact', 'Verdana', 'Georgia', 'Comic Sans MS', 'Calibri']
    : ['sans-serif', 'sans-serif-condensed', 'sans-serif-light', 'sans-serif-black', 'serif', 'monospace', 'cursive', 'casual'];

class TextSpec {
  String text, font;
  double size, rotation, opacity;
  Color color, outlineColor, boxColor;
  bool bold, italic, outline, shadow, box;
  TextSpec(
      {this.text = 'Media Editor',
      this.font = '',
      this.size = 8,
      this.rotation = 0,
      this.opacity = 1,
      this.color = Colors.white,
      this.outlineColor = Colors.black,
      this.boxColor = Colors.black,
      this.bold = true,
      this.italic = false,
      this.outline = false,
      this.shadow = true,
      this.box = false});
}

class TextArt {
  final TextSpec s;
  final double fs;
  late final TextPainter fill;
  TextPainter? line;
  late final double pad;
  late final Size inner;

  TextArt(this.s, this.fs) {
    final ar = RegExp(r'[\u0600-\u06FF]').hasMatch(s.text);
    final dir = ar ? TextDirection.rtl : TextDirection.ltr;
    final a = (s.opacity * 255).round();
    TextStyle base({Color? c, Paint? fg, bool sh = false}) => TextStyle(
          fontFamily: s.font.isEmpty ? null : s.font,
          fontSize: fs,
          fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
          color: fg == null ? c : null,
          foreground: fg,
          height: 1.15,
          shadows: sh
              ? [Shadow(blurRadius: fs * 0.1, offset: Offset(fs * 0.04, fs * 0.04), color: const Color(0xAA000000))]
              : null,
        );
    fill = TextPainter(
        text: TextSpan(text: s.text, style: base(c: s.color.withAlpha(a), sh: s.shadow && !s.box)),
        textDirection: dir,
        textAlign: TextAlign.center)
      ..layout();
    if (s.outline) {
      line = TextPainter(
          text: TextSpan(
              text: s.text,
              style: base(
                  fg: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = fs * 0.14
                    ..strokeJoin = StrokeJoin.round
                    ..color = s.outlineColor.withAlpha(a))),
          textDirection: dir,
          textAlign: TextAlign.center)
        ..layout();
    }
    pad = s.box ? fs * 0.35 : fs * 0.15;
    inner = Size(fill.width, fill.height);
  }

  Size get flat => Size(inner.width + 2 * pad, inner.height + 2 * pad);
  Size get bounds {
    final r = s.rotation * math.pi / 180;
    final c = math.cos(r).abs(), n = math.sin(r).abs();
    final f = flat;
    return Size((f.width * c + f.height * n).ceilToDouble(),
        (f.width * n + f.height * c).ceilToDouble());
  }

  void paint(Canvas c, Size area) {
    c.save();
    c.translate(area.width / 2, area.height / 2);
    c.rotate(s.rotation * math.pi / 180);
    if (s.box) {
      final f = flat;
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: f.width, height: f.height),
              Radius.circular(fs * 0.25)),
          Paint()..color = s.boxColor.withAlpha((0.6 * s.opacity * 255).round()));
    }
    final o = Offset(-fill.width / 2, -fill.height / 2);
    line?.paint(c, o);
    fill.paint(c, o);
    c.restore();
  }
}

/// Logo (optional) above text (optional); used for preview and for final render.
class Group {
  final TextArt? art;
  final ui.Image? logo;
  final double lw, op, rot;
  late final double lh, lbw, lbh, gap;
  late final Size size;
  Group({this.art, this.logo, this.lw = 0, this.op = 1, this.rot = 0}) {
    lh = logo == null ? 0 : logo!.height * lw / logo!.width;
    final r = rot * math.pi / 180;
    final c = math.cos(r).abs(), n = math.sin(r).abs();
    lbw = logo == null ? 0 : lw * c + lh * n;
    lbh = logo == null ? 0 : lw * n + lh * c;
    final tb = art?.bounds ?? Size.zero;
    gap = (art != null && logo != null) ? tb.height * 0.1 : 0;
    size = Size(math.max(lbw, tb.width), lbh + gap + tb.height);
  }

  void paint(Canvas c) {
    if (logo != null) {
      c.save();
      c.translate(size.width / 2, lbh / 2);
      c.rotate(rot * math.pi / 180);
      c.drawImageRect(
          logo!,
          Rect.fromLTWH(0, 0, logo!.width.toDouble(), logo!.height.toDouble()),
          Rect.fromCenter(center: Offset.zero, width: lw, height: lh),
          Paint()
            ..color = Color.fromARGB((op * 255).round(), 255, 255, 255)
            ..filterQuality = FilterQuality.high);
      c.restore();
    }
    if (art != null) {
      final tb = art!.bounds;
      c.save();
      c.translate((size.width - tb.width) / 2, lbh + gap);
      art!.paint(c, tb);
      c.restore();
    }
  }
}

class GroupPainter extends CustomPainter {
  final Group g;
  GroupPainter(this.g);
  @override
  void paint(Canvas c, Size s) => g.paint(c);
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

void paintTiled(Canvas c, Size area, Group g) {
  if (g.size.width < 1 || g.size.height < 1) return;
  c.save();
  c.translate(area.width / 2, area.height / 2);
  c.rotate(-0.5);
  final sx = g.size.width * 1.8, sy = g.size.height * 3;
  final span = math.max(area.width, area.height);
  for (var y = -span; y < span; y += sy) {
    for (var x = -span; x < span; x += sx) {
      c.save();
      c.translate(x, y);
      g.paint(c);
      c.restore();
    }
  }
  c.restore();
}

class TilePainter extends CustomPainter {
  final Group g;
  TilePainter(this.g);
  @override
  void paint(Canvas c, Size s) => paintTiled(c, s, g);
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

Future<Uint8List> renderPng(Size s, void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final im = await rec.endRecording().toImage(s.width.ceil(), s.height.ceil());
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

Future<ui.Image> decodeUi(Uint8List b) async =>
    (await (await ui.instantiateImageCodec(b)).getNextFrame()).image;

// ---------- UI helpers ----------
Widget labeledSlider(String label, double v, double min, double max,
        ValueChanged<double> f, {int? div}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ${v.toStringAsFixed(max <= 2 ? 2 : 0)}'),
      Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, divisions: div, onChanged: f),
    ]);

class ColorPick extends StatelessWidget {
  final Color value;
  final ValueChanged<Color> onChanged;
  const ColorPick({super.key, required this.value, required this.onChanged});

  Future<void> custom(BuildContext context) async {
    var c = value;
    final r = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t(ctx, 'لون مخصص', 'Custom color')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8))),
            for (final ch in [0, 1, 2])
              Slider(
                  value: [c.red, c.green, c.blue][ch].toDouble(),
                  min: 0,
                  max: 255,
                  onChanged: (x) => set(() => c = Color.fromARGB(255, ch == 0 ? x.round() : c.red, ch == 1 ? x.round() : c.green, ch == 2 ? x.round() : c.blue))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, c), child: Text(t(ctx, 'موافق', 'OK'))),
          ],
        ),
      ),
    );
    if (r != null) onChanged(r);
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in palette)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                      width: value.value == c.value ? 3 : 1,
                      color: value.value == c.value
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey)),
            ),
          ),
        GestureDetector(
          onTap: () => custom(context),
          child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey)),
              child: const Icon(Icons.colorize, size: 16)),
        ),
      ]);
}

class TextEditorPanel extends StatefulWidget {
  final TextSpec s;
  final VoidCallback onChanged;
  const TextEditorPanel({super.key, required this.s, required this.onChanged});
  @override
  State<TextEditorPanel> createState() => _TextEditorPanelState();
}

class _TextEditorPanelState extends State<TextEditorPanel> {
  late final ctrl = TextEditingController(text: widget.s.text);
  void up(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    Widget gap() => const SizedBox(height: 10);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: ctrl,
          maxLines: null,
          onChanged: (x) {
            s.text = x;
            widget.onChanged();
          },
          decoration: InputDecoration(labelText: t(context, 'النص', 'Text'), border: const OutlineInputBorder())),
      gap(),
      Text(t(context, 'نمط الخط', 'Font style')),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: Text(t(context, 'افتراضي', 'Default')), selected: s.font.isEmpty, onSelected: (_) => up(() => s.font = '')),
        for (final f in fontList)
          ChoiceChip(
              label: Text(f, style: TextStyle(fontFamily: f)),
              selected: s.font == f,
              onSelected: (_) => up(() => s.font = f)),
      ]),
      gap(),
      labeledSlider(t(context, 'الحجم', 'Size'), s.size, 1, 30, (x) => up(() => s.size = x)),
      labeledSlider(t(context, 'التدوير', 'Rotation'), s.rotation, -180, 180, (x) => up(() => s.rotation = x.roundToDouble())),
      labeledSlider(t(context, 'الشفافية', 'Opacity'), s.opacity, 0.1, 1, (x) => up(() => s.opacity = x)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        FilterChip(label: Text(t(context, 'عريض', 'Bold')), selected: s.bold, onSelected: (x) => up(() => s.bold = x)),
        FilterChip(label: Text(t(context, 'مائل', 'Italic')), selected: s.italic, onSelected: (x) => up(() => s.italic = x)),
        FilterChip(label: Text(t(context, 'حد خارجي', 'Outline')), selected: s.outline, onSelected: (x) => up(() => s.outline = x)),
        FilterChip(label: Text(t(context, 'ظل', 'Shadow')), selected: s.shadow, onSelected: (x) => up(() => s.shadow = x)),
        FilterChip(label: Text(t(context, 'خلفية', 'Box')), selected: s.box, onSelected: (x) => up(() => s.box = x)),
      ]),
      gap(),
      Text(t(context, 'لون النص', 'Text color')),
      const SizedBox(height: 6),
      ColorPick(value: s.color, onChanged: (c) => up(() => s.color = c)),
      if (s.outline) ...[
        gap(),
        Text(t(context, 'لون الحد', 'Outline color')),
        const SizedBox(height: 6),
        ColorPick(value: s.outlineColor, onChanged: (c) => up(() => s.outlineColor = c)),
      ],
      if (s.box) ...[
        gap(),
        Text(t(context, 'لون الخلفية', 'Box color')),
        const SizedBox(height: 6),
        ColorPick(value: s.boxColor, onChanged: (c) => up(() => s.boxColor = c)),
      ],
    ]);
  }
}
