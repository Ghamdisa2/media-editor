import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'strings.dart';
import 'tool_screen.dart';

/// Text on image / watermark on one or many images. Drawn with Flutter's
/// text engine, so Arabic shaping and RTL work correctly.
class OverlayTool extends StatefulWidget {
  final bool watermark;
  const OverlayTool({super.key, required this.watermark});
  @override
  State<OverlayTool> createState() => _OverlayToolState();
}

class _OverlayToolState extends State<OverlayTool> {
  final srcs = <Uint8List>[];
  final names = <String>[];
  final outs = <Uint8List>[];
  Uint8List? logo;
  late final text = TextEditingController(text: widget.watermark ? '© Media Editor' : '');
  double size = 6, opacity = 1, logoSize = 20;
  int color = 0, pos = 3;
  bool busy = false;

  static const colors = [Colors.white, Colors.black, Colors.yellow, Colors.red];

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: widget.watermark, withData: true);
    if (r == null) return;
    setState(() {
      srcs.clear();
      names.clear();
      outs.clear();
      for (final f in r.files) {
        if (f.bytes != null) {
          srcs.add(f.bytes!);
          names.add(f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name);
        }
      }
    });
  }

  Future<void> pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r?.files.single.bytes != null) setState(() => logo = r!.files.single.bytes);
  }

  Future<ui.Image> _decode(Uint8List b) async =>
      (await (await ui.instantiateImageCodec(b)).getNextFrame()).image;

  Future<Uint8List> render(Uint8List src) async {
    final im = await _decode(src);
    final w = im.width.toDouble(), h = im.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(im, Offset.zero, Paint());
    final alpha = (opacity * 255).round();
    final txt = text.text.trim();
    final isAr = RegExp(r'[\u0600-\u06FF]').hasMatch(txt);
    TextPainter? tp;
    if (txt.isNotEmpty) {
      tp = TextPainter(
        text: TextSpan(
            text: txt,
            style: TextStyle(
                color: colors[color].withAlpha(alpha),
                fontSize: w * size / 100,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(blurRadius: 4, color: Color(0x88000000))])),
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: w * 0.9);
    }
    ui.Image? lg;
    double lw = 0, lh = 0;
    if (logo != null) {
      lg = await _decode(logo!);
      lw = w * logoSize / 100;
      lh = lg.height * lw / lg.width;
    }
    final gap = (tp != null && lg != null) ? h * 0.01 : 0.0;
    final itemW = [tp?.width ?? 0.0, lw].reduce((a, b) => a > b ? a : b);
    final itemH = (tp?.height ?? 0.0) + lh + gap;
    void item(double x, double y) {
      if (lg != null) {
        c.drawImageRect(
            lg,
            Rect.fromLTWH(0, 0, lg.width.toDouble(), lg.height.toDouble()),
            Rect.fromLTWH(x + (itemW - lw) / 2, y, lw, lh),
            Paint()
              ..color = Color.fromARGB(alpha, 255, 255, 255)
              ..filterQuality = FilterQuality.high);
      }
      tp?.paint(c, Offset(x + (itemW - tp.width) / 2, y + lh + gap));
    }

    if (itemW > 0) {
      final m = w * 0.03;
      switch (pos) {
        case 0: item(m, m);
        case 1: item(w - itemW - m, m);
        case 2: item(m, h - itemH - m);
        case 3: item(w - itemW - m, h - itemH - m);
        case 4: item((w - itemW) / 2, (h - itemH) / 2);
        default:
          c.save();
          c.translate(w / 2, h / 2);
          c.rotate(-0.5);
          final sx = itemW * 1.8, sy = itemH * 3;
          for (var y = -h; y < h; y += sy) {
            for (var x = -w; x < w; x += sx) {
              item(x, y);
            }
          }
          c.restore();
      }
    }
    final out = await rec.endRecording().toImage(im.width, im.height);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      final r = <Uint8List>[];
      for (final s in srcs) {
        r.add(await render(s));
      }
      if (mounted) setState(() { outs..clear()..addAll(r); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (outs.isEmpty) return;
    String? p;
    if (outs.length == 1) {
      p = await saveBytes('${names[0]}_${widget.watermark ? 'wm' : 'text'}.png', outs[0]);
    } else {
      final a = Archive();
      for (var i = 0; i < outs.length; i++) {
        a.addFile(ArchiveFile('${names[i]}_wm.png', outs[i].length, outs[i]));
      }
      p = await saveBytes('watermarked.zip', Uint8List.fromList(ZipEncoder().encode(a)!));
    }
    if (p != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

  Widget slider(String label, double v, double min, double max, ValueChanged<double> f) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label: ${v.toStringAsFixed(max <= 1 ? 2 : 0)}'),
        Slider(value: v, min: min, max: max, onChanged: (x) => setState(() => f(x))),
      ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final panel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.tonalIcon(
          onPressed: pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(widget.watermark
              ? t(context, 'اختيار صورة أو أكثر', 'Choose image(s)')
              : t(context, 'اختيار صورة', 'Choose image'))),
      const SizedBox(height: 12),
      TextField(
          controller: text,
          decoration: InputDecoration(
              labelText: t(context, 'النص', 'Text'), border: const OutlineInputBorder())),
      if (widget.watermark) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: pickLogo,
            icon: const Icon(Icons.image_outlined),
            label: Text(logo == null
                ? t(context, 'إضافة شعار (اختياري)', 'Add logo (optional)')
                : t(context, 'تغيير الشعار', 'Change logo'))),
        if (logo != null) slider(t(context, 'حجم الشعار %', 'Logo size %'), logoSize, 5, 60, (x) => logoSize = x),
      ],
      const SizedBox(height: 8),
      slider(t(context, 'حجم الخط %', 'Font size %'), size, 2, 20, (x) => size = x),
      slider(t(context, 'الشفافية', 'Opacity'), opacity, 0.1, 1, (x) => opacity = x),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < 4; i++)
          ChoiceChip(
              label: Text(t(context, ['أبيض', 'أسود', 'أصفر', 'أحمر'][i], ['White', 'Black', 'Yellow', 'Red'][i])),
              selected: color == i,
              onSelected: (_) => setState(() => color = i)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < (widget.watermark ? 6 : 5); i++)
          ChoiceChip(
              label: Text(t(context,
                  ['أعلى يسار', 'أعلى يمين', 'أسفل يسار', 'أسفل يمين', 'وسط', 'تكرار'][i],
                  ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center', 'Tiled'][i])),
              selected: pos == i,
              onSelected: (_) => setState(() => pos = i)),
      ]),
      const SizedBox(height: 12),
      FilledButton(
          onPressed: srcs.isEmpty || busy ? null : apply,
          child: busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t(context, 'تطبيق', 'Apply'))),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: outs.isEmpty ? null : save,
          icon: const Icon(Icons.save_alt),
          label: Text(outs.length > 1 ? t(context, 'حفظ (ZIP)', 'Save (ZIP)') : t(context, 'حفظ', 'Save'))),
    ]);
    final shown = outs.isNotEmpty ? outs.first : (srcs.isNotEmpty ? srcs.first : null);
    final preview = Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: shown == null
          ? Text(t(context, 'اختر صورة للبدء', 'Choose an image to start'))
          : Padding(padding: const EdgeInsets.all(8), child: Image.memory(shown, fit: BoxFit.contain)),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 800) {
          return Row(children: [
            SizedBox(width: 340, child: SingleChildScrollView(child: panel)),
            const SizedBox(width: 16),
            Expanded(child: preview),
          ]);
        }
        return Column(children: [
          Expanded(child: preview),
          const SizedBox(height: 12),
          SizedBox(height: 320, child: SingleChildScrollView(child: panel)),
        ]);
      }),
    );
  }
}
