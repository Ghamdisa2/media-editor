import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'art.dart';
import 'strings.dart';
import 'tool_screen.dart';

const _icons = <IconData>[
  Icons.star, Icons.favorite, Icons.bolt, Icons.camera_alt, Icons.music_note, Icons.movie,
  Icons.brush, Icons.rocket_launch, Icons.pets, Icons.local_cafe, Icons.shopping_bag, Icons.code,
  Icons.school, Icons.sports_soccer, Icons.eco, Icons.diamond,
];

class _DesignPainter extends CustomPainter {
  final TextSpec spec;
  final int shape, icon;
  final Color bg1, bg2, border, iconColor;
  final bool gradient;
  final double borderW, iconSize;
  _DesignPainter(this.spec, this.shape, this.icon, this.bg1, this.bg2, this.border, this.iconColor,
      this.gradient, this.borderW, this.iconSize);

  @override
  void paint(Canvas c, Size s) {
    final rect = (Offset.zero & s).deflate(s.shortestSide * 0.04);
    if (shape > 0) {
      final p = Paint();
      if (gradient) {
        p.shader = LinearGradient(colors: [bg1, bg2], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(rect);
      } else {
        p.color = bg1;
      }
      void draw(Paint paint) {
        switch (shape) {
          case 1:
            c.drawOval(rect, paint);
          case 2:
            c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide * 0.22)), paint);
          case 3:
            c.drawRect(rect, paint);
          default:
            c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)), paint);
        }
      }

      draw(p);
      if (borderW > 0) {
        draw(Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.shortestSide * borderW / 100
          ..color = border);
      }
    }
    final hasText = spec.text.trim().isNotEmpty;
    if (icon >= 0) {
      final ic = _icons[icon];
      final tp = TextPainter(
          text: TextSpan(
              text: String.fromCharCode(ic.codePoint),
              style: TextStyle(fontFamily: ic.fontFamily, package: ic.fontPackage, fontSize: s.shortestSide * iconSize / 100, color: iconColor)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset((s.width - tp.width) / 2, s.height * (hasText ? 0.38 : 0.5) - tp.height / 2));
    }
    if (hasText) {
      final a = TextArt(spec, s.shortestSide * spec.size / 100);
      final b = a.bounds;
      c.save();
      c.translate((s.width - b.width) / 2, s.height * (icon >= 0 ? 0.74 : 0.5) - b.height / 2);
      a.paint(c, b);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// Logo designer (square canvas) and watermark designer (wide canvas, transparent).
class DesignerTool extends StatefulWidget {
  final bool logo;
  const DesignerTool({super.key, required this.logo});
  @override
  State<DesignerTool> createState() => _DesignerToolState();
}

class _DesignerToolState extends State<DesignerTool> {
  late final spec = TextSpec(text: widget.logo ? 'LOGO' : '© Media Editor', size: widget.logo ? 14 : 12);
  late int shape = widget.logo ? 1 : 0;
  int icon = -1;
  Color bg1 = const Color(0xFF0E7C86), bg2 = const Color(0xFF34C759), border = Colors.white, iconColor = Colors.white;
  bool gradient = true;
  double borderW = 0, iconSize = 34;

  Size get canvas => widget.logo ? const Size(1024, 1024) : const Size(1024, 420);

  _DesignPainter painter() => _DesignPainter(spec, shape, icon, bg1, bg2, border, iconColor, gradient, borderW, iconSize);

  Future<void> save() async {
    final p = painter();
    final png = await renderPng(canvas, (c) => p.paint(c, canvas));
    final path = await saveBytes(widget.logo ? 'logo.png' : 'watermark.png', png);
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    void up(VoidCallback f) => setState(f);
    final shapes = [
      (t(context, 'بدون', 'None')), t(context, 'دائرة', 'Circle'), t(context, 'مربع دائري', 'Rounded'),
      t(context, 'مربع', 'Square'), t(context, 'كبسولة', 'Pill'),
    ];
    final panel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextEditorPanel(s: spec, onChanged: () => setState(() {})),
      const Divider(height: 24),
      Text(t(context, 'الشكل', 'Shape')),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < shapes.length; i++)
          ChoiceChip(label: Text(shapes[i]), selected: shape == i, onSelected: (_) => up(() => shape = i)),
      ]),
      if (shape > 0) ...[
        const SizedBox(height: 10),
        Text(t(context, 'لون الخلفية', 'Background color')),
        const SizedBox(height: 6),
        ColorPick(value: bg1, onChanged: (c) => up(() => bg1 = c)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t(context, 'تدرج لوني', 'Gradient')),
            value: gradient,
            onChanged: (x) => up(() => gradient = x)),
        if (gradient) ColorPick(value: bg2, onChanged: (c) => up(() => bg2 = c)),
        labeledSlider(t(context, 'سماكة الحد', 'Border width'), borderW, 0, 8, (x) => up(() => borderW = x)),
        if (borderW > 0) ColorPick(value: border, onChanged: (c) => up(() => border = c)),
      ],
      if (widget.logo) ...[
        const Divider(height: 24),
        Text(t(context, 'أيقونة', 'Icon')),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(label: Text(t(context, 'بدون', 'None')), selected: icon < 0, onSelected: (_) => up(() => icon = -1)),
          for (var i = 0; i < _icons.length; i++)
            ChoiceChip(label: Icon(_icons[i], size: 20), selected: icon == i, onSelected: (_) => up(() => icon = i)),
        ]),
        if (icon >= 0) ...[
          labeledSlider(t(context, 'حجم الأيقونة', 'Icon size'), iconSize, 10, 70, (x) => up(() => iconSize = x)),
          ColorPick(value: iconColor, onChanged: (c) => up(() => iconColor = c)),
        ],
      ],
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: save, icon: const Icon(Icons.save_alt), label: Text(t(context, 'حفظ PNG', 'Save PNG'))),
    ]);
    final prev = Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: AspectRatio(
        aspectRatio: canvas.width / canvas.height,
        child: LayoutBuilder(builder: (_, c) {
          return ClipRect(
              child: FittedBox(
                  child: SizedBox(
                      width: canvas.width,
                      height: canvas.height,
                      child: CustomPaint(painter: painter()))));
        }),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 800) {
          return Row(children: [
            SizedBox(width: 360, child: SingleChildScrollView(child: panel)),
            const SizedBox(width: 16),
            Expanded(child: prev),
          ]);
        }
        return Column(children: [
          Expanded(flex: 4, child: prev),
          const SizedBox(height: 8),
          Expanded(flex: 5, child: SingleChildScrollView(child: panel)),
        ]);
      }),
    );
  }
}
