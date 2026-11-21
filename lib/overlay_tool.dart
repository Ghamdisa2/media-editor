import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'art.dart';
import 'strings.dart';
import 'tool_screen.dart';

/// Text on image / watermark on one or many images.
/// Drag the overlay on the preview, rotate, change font style and colors.
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
  Size imgSize = const Size(16, 9);
  ui.Image? logo;
  late final spec = TextSpec(text: widget.watermark ? '© Media Editor' : 'Media Editor', size: widget.watermark ? 5 : 8);
  Offset pos = const Offset(0.5, 0.5);
  bool tile = false, busy = false;
  double logoSize = 20, logoOp = 1, logoRot = 0;

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: widget.watermark, withData: true);
    if (r == null) return;
    final list = r.files.where((f) => f.bytes != null).toList();
    if (list.isEmpty) return;
    final u = await decodeUi(list.first.bytes!);
    setState(() {
      srcs..clear()..addAll(list.map((f) => f.bytes!));
      names
        ..clear()
        ..addAll(list.map((f) => f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name));
      outs.clear();
      imgSize = Size(u.width.toDouble(), u.height.toDouble());
    });
  }

  Future<void> pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final b = r?.files.single.bytes;
    if (b == null) return;
    final u = await decodeUi(b);
    setState(() => logo = u);
  }

  Group group(double w) => Group(
        art: spec.text.trim().isEmpty ? null : TextArt(spec, w * spec.size / 100),
        logo: logo,
        lw: w * logoSize / 100,
        op: logoOp,
        rot: logoRot,
      );

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      final r = <Uint8List>[];
      for (final s in srcs) {
        final im = await decodeUi(s);
        final w = im.width.toDouble(), h = im.height.toDouble();
        final g = group(w);
        r.add(await renderPng(Size(w, h), (c) {
          c.drawImage(im, Offset.zero, Paint());
          if (tile) {
            paintTiled(c, Size(w, h), g);
          } else {
            c.save();
            c.translate(pos.dx * w - g.size.width / 2, pos.dy * h - g.size.height / 2);
            g.paint(c);
            c.restore();
          }
        }));
      }
      if (mounted) setState(() => outs..clear()..addAll(r));
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
      p = await saveBytes('${names[0]}_edited.png', outs[0]);
    } else {
      final a = Archive();
      for (var i = 0; i < outs.length; i++) {
        a.addFile(ArchiveFile('${names[i]}_edited.png', outs[i].length, outs[i]));
      }
      p = await saveBytes('images.zip', Uint8List.fromList(ZipEncoder().encode(a)!));
    }
    if (p != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

  Widget preview(BoxConstraints c) {
    if (srcs.isEmpty) return Center(child: Text(t(context, 'اختر صورة للبدء', 'Choose an image to start')));
    final fit = applyBoxFit(BoxFit.contain, Size(imgSize.width / imgSize.height, 1), c.biggest).destination;
    final shownOut = outs.isNotEmpty;
    final g = group(fit.width);
    final hasItem = g.size.width > 1 && g.size.height > 1;
    return Center(
      child: SizedBox(
        width: fit.width,
        height: fit.height,
        child: Stack(children: [
          Positioned.fill(child: Image.memory(shownOut ? outs.first : srcs.first, fit: BoxFit.fill)),
          if (!shownOut && hasItem && tile) Positioned.fill(child: CustomPaint(painter: TilePainter(g))),
          if (!shownOut && hasItem && !tile)
            Positioned(
              left: pos.dx * fit.width - g.size.width / 2,
              top: pos.dy * fit.height - g.size.height / 2,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => pos = Offset(
                    (pos.dx + d.delta.dx / fit.width).clamp(0.0, 1.0).toDouble(),
                    (pos.dy + d.delta.dy / fit.height).clamp(0.0, 1.0).toDouble())),
                child: CustomPaint(size: g.size, painter: GroupPainter(g)),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final panel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.tonalIcon(
          onPressed: pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(widget.watermark ? t(context, 'اختيار صورة أو أكثر', 'Choose image(s)') : t(context, 'اختيار صورة', 'Choose image'))),
      const SizedBox(height: 12),
      TextEditorPanel(s: spec, onChanged: () => setState(() => outs.clear())),
      if (widget.watermark) ...[
        const Divider(height: 24),
        OutlinedButton.icon(
            onPressed: pickLogo,
            icon: const Icon(Icons.image_outlined),
            label: Text(logo == null ? t(context, 'إضافة شعار (اختياري)', 'Add logo (optional)') : t(context, 'تغيير الشعار', 'Change logo'))),
        if (logo != null) ...[
          labeledSlider(t(context, 'حجم الشعار %', 'Logo size %'), logoSize, 3, 80, (x) => setState(() => logoSize = x)),
          labeledSlider(t(context, 'تدوير الشعار', 'Logo rotation'), logoRot, -180, 180, (x) => setState(() => logoRot = x.roundToDouble())),
          labeledSlider(t(context, 'شفافية الشعار', 'Logo opacity'), logoOp, 0.1, 1, (x) => setState(() => logoOp = x)),
        ],
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t(context, 'تكرار على كامل الصورة', 'Tile over whole image')),
            value: tile,
            onChanged: (x) => setState(() => tile = x)),
      ],
      Text(t(context, 'اسحب العنصر على الصورة لتحديد مكانه', 'Drag the item on the image to place it'),
          style: TextStyle(color: cs.outline, fontSize: 12)),
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
    final prev = Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (_, c) => preview(c)),
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
          Expanded(flex: 5, child: prev),
          const SizedBox(height: 8),
          Expanded(flex: 4, child: SingleChildScrollView(child: panel)),
        ]);
      }),
    );
  }
}
