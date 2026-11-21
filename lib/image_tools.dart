import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'strings.dart';
import 'tool_screen.dart';

// ---------- processing (top-level so they run in an isolate) ----------
typedef Vals = Map<String, double>;

img.Image _dec(Uint8List b) {
  final i = img.decodeImage(b);
  if (i == null) throw 'Unsupported image';
  return i;
}

Uint8List flipRun(Uint8List b, Vals v) {
  final d = v['dir']!.round();
  final i = img.flip(_dec(b),
      direction: d == 0
          ? img.FlipDirection.horizontal
          : d == 1
              ? img.FlipDirection.vertical
              : img.FlipDirection.both);
  return img.encodePng(i);
}

Uint8List blurRun(Uint8List b, Vals v) =>
    img.encodePng(img.gaussianBlur(_dec(b), radius: v['r']!.round()));

Uint8List enhanceRun(Uint8List b, Vals v) => img.encodePng(img.adjustColor(
    _dec(b),
    brightness: v['b'],
    contrast: v['c'],
    saturation: v['s']));

Uint8List compressRun(Uint8List b, Vals v) {
  var i = _dec(b);
  final s = v['w']! / 100;
  if (s < 1) i = img.copyResize(i, width: math.max(1, (i.width * s).round()));
  return img.encodeJpg(i, quality: v['q']!.round());
}

Uint8List convertRun(Uint8List b, Vals v) {
  final i = _dec(b);
  return switch (v['f']!.round()) {
    0 => img.encodeJpg(i, quality: 92),
    1 => img.encodePng(i),
    _ => img.encodeBmp(i),
  };
}

Uint8List cropRun(Uint8List b, Vals v) {
  final i = _dec(b);
  final x = (i.width * v['x']! / 100).round().clamp(0, i.width - 1);
  final y = (i.height * v['y']! / 100).round().clamp(0, i.height - 1);
  final w = (i.width * v['w']! / 100).round().clamp(1, i.width - x);
  final h = (i.height * v['h']! / 100).round().clamp(1, i.height - y);
  return img.encodePng(img.copyCrop(i, x: x, y: y, width: w, height: h));
}

Future<Uint8List> runImageIso(
        Uint8List Function(Uint8List, Vals) run, Uint8List src, Vals v) =>
    Isolate.run(() => run(src, v));

Future<Uint8List> runMultiIso(int mode, List<Uint8List> files, Vals v) =>
    Isolate.run(() async {
      switch (mode) {
        case 0:
          return mergeRun(files, v);
        case 1:
          return await pdfRun(files, v);
        case 2:
          return collageRun(files, v);
        default:
          return blendRun(files, v);
      }
    });

/// Background remover: removes the colour found around the image border.
Uint8List bgRun(Uint8List b, Vals v) {
  final i = _dec(b).convert(numChannels: 4);
  final w = i.width, h = i.height;
  double r = 0, g = 0, bl = 0;
  var n = 0;
  void acc(int x, int y) {
    final p = i.getPixel(x, y);
    r += p.r;
    g += p.g;
    bl += p.b;
    n++;
  }
  for (var x = 0; x < w; x++) {
    acc(x, 0);
    acc(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    acc(0, y);
    acc(w - 1, y);
  }
  r /= n;
  g /= n;
  bl /= n;
  final tol = v['t']! * 4.4;
  bool isBg(int x, int y) {
    final p = i.getPixel(x, y);
    final dr = p.r - r, dg = p.g - g, db = p.b - bl;
    return math.sqrt(dr * dr + dg * dg + db * db) <= tol;
  }

  final mask = Uint8List(w * h)..fillRange(0, w * h, 255);
  if (v['m']!.round() == 1) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (isBg(x, y)) mask[y * w + x] = 0;
      }
    }
  } else {
    final stack = <int>[];
    void push(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final k = y * w + x;
      if (mask[k] == 0 || !isBg(x, y)) return;
      mask[k] = 0;
      stack.add(k);
    }
    for (var x = 0; x < w; x++) {
      push(x, 0);
      push(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      push(0, y);
      push(w - 1, y);
    }
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      final x = k % w, y = k ~/ w;
      push(x + 1, y);
      push(x - 1, y);
      push(x, y + 1);
      push(x, y - 1);
    }
  }
  final f = v['f']!.round();
  if (f > 0) {
    final m = img.Image(width: w, height: h, numChannels: 1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        m.setPixelR(x, y, mask[y * w + x]);
      }
    }
    img.gaussianBlur(m, radius: f);
    for (final p in i) {
      p.a = m.getPixel(p.x, p.y).r;
    }
  } else {
    for (final p in i) {
      p.a = mask[p.y * w + p.x];
    }
  }
  return img.encodePng(i);
}

// ---------- single image tool ----------
class Opt {
  final String key, ar, en;
  final double min, max, def;
  final int? divisions;
  final List<(String, String)>? choices;
  const Opt(this.key, this.ar, this.en, this.min, this.max, this.def,
      {this.divisions, this.choices});
}

class ImageTool extends StatefulWidget {
  final List<Opt> opts;
  final Uint8List Function(Uint8List, Vals) run;
  final String Function(Vals) ext;
  final String suffix;
  const ImageTool(
      {super.key,
      required this.opts,
      required this.run,
      required this.ext,
      required this.suffix});
  @override
  State<ImageTool> createState() => _ImageToolState();
}

class _ImageToolState extends State<ImageTool> {
  Uint8List? src, out;
  String name = 'image';
  bool busy = false;
  late Vals v = {for (final o in widget.opts) o.key: o.def};

  Future<void> pick() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f?.bytes == null) return;
    setState(() {
      src = f!.bytes;
      name = f.name.contains('.')
          ? f.name.substring(0, f.name.lastIndexOf('.'))
          : f.name;
      out = null;
    });
  }

  Future<void> apply() async {
    final s = src;
    if (s == null) return;
    setState(() => busy = true);
    final run = widget.run;
    final vals = Vals.of(v);
    try {
      final r = await runImageIso(run, s, vals);
      if (mounted) setState(() => out = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final o = out;
    if (o == null) return;
    final p = await saveBytes(
        '${name}_${widget.suffix}.${widget.ext(v)}', o);
    if (p != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

  Widget control(Opt o) {
    final label = t(context, o.ar, o.en);
    if (o.choices != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < o.choices!.length; i++)
              ButtonSegment(
                  value: i,
                  label: Text(t(context, o.choices![i].$1, o.choices![i].$2)))
          ],
          selected: {v[o.key]!.round()},
          onSelectionChanged: (s) =>
              setState(() => v[o.key] = s.first.toDouble()),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ${v[o.key]!.toStringAsFixed(o.max <= 2 ? 2 : 0)}'),
      Slider(
          value: v[o.key]!,
          min: o.min,
          max: o.max,
          divisions: o.divisions,
          onChanged: (x) => setState(() => v[o.key] = x)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
            onPressed: pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(t(context, 'اختيار صورة', 'Choose image'))),
        const SizedBox(height: 16),
        for (final o in widget.opts) ...[control(o), const SizedBox(height: 8)],
        const SizedBox(height: 8),
        FilledButton(
            onPressed: src == null || busy ? null : apply,
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t(context, 'تطبيق', 'Apply'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: out == null ? null : save,
            icon: const Icon(Icons.save_alt),
            label: Text(t(context, 'حفظ', 'Save'))),
      ],
    );
    final preview = Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: (out ?? src) == null
          ? Text(t(context, 'اختر صورة للبدء', 'Choose an image to start'))
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Image.memory(out ?? src!, fit: BoxFit.contain)),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 800) {
          return Row(children: [
            SizedBox(width: 320, child: SingleChildScrollView(child: panel)),
            const SizedBox(width: 16),
            Expanded(child: preview),
          ]);
        }
        return Column(children: [
          Expanded(child: preview),
          const SizedBox(height: 12),
          SizedBox(
              height: 300, child: SingleChildScrollView(child: panel)),
        ]);
      }),
    );
  }
}

// ---------- multi image tools: merge and PDF ----------
enum MultiMode { merge, pdf, collage, blend }

Uint8List mergeRun(List<Uint8List> files, Vals v) {
  final imgs = files.map(_dec).toList();
  final horiz = v['d']!.round() == 1;
  final gap = v['g']!.round();
  if (horiz) {
    final h = imgs.map((e) => e.height).reduce(math.max);
    final r = imgs
        .map((e) => img.copyResize(e, height: h))
        .toList();
    final w = r.fold<int>(0, (s, e) => s + e.width) + gap * (r.length - 1);
    final d = img.Image(width: w, height: h, numChannels: 4);
    img.fill(d, color: img.ColorRgba8(255, 255, 255, 255));
    var x = 0;
    for (final e in r) {
      img.compositeImage(d, e, dstX: x, dstY: 0);
      x += e.width + gap;
    }
    return img.encodePng(d);
  }
  final w = imgs.map((e) => e.width).reduce(math.max);
  final r = imgs.map((e) => img.copyResize(e, width: w)).toList();
  final h = r.fold<int>(0, (s, e) => s + e.height) + gap * (r.length - 1);
  final d = img.Image(width: w, height: h, numChannels: 4);
  img.fill(d, color: img.ColorRgba8(255, 255, 255, 255));
  var y = 0;
  for (final e in r) {
    img.compositeImage(d, e, dstX: 0, dstY: y);
    y += e.height + gap;
  }
  return img.encodePng(d);
}

Uint8List collageRun(List<Uint8List> files, Vals v) {
  final cols = v['c']!.round() == 0 ? 2 : 3;
  final gap = v['g']!.round();
  const cell = 600;
  final imgs = files.map(_dec).toList();
  final rows = (imgs.length / cols).ceil();
  final d = img.Image(
      width: cols * cell + gap * (cols + 1),
      height: rows * cell + gap * (rows + 1),
      numChannels: 4);
  img.fill(d, color: img.ColorRgba8(255, 255, 255, 255));
  for (var k = 0; k < imgs.length; k++) {
    final s = imgs[k];
    final sc = math.max(cell / s.width, cell / s.height);
    final r = img.copyResize(s,
        width: (s.width * sc).ceil(), height: (s.height * sc).ceil());
    final c = img.copyCrop(r,
        x: (r.width - cell) ~/ 2, y: (r.height - cell) ~/ 2, width: cell, height: cell);
    img.compositeImage(d, c,
        dstX: gap + (k % cols) * (cell + gap), dstY: gap + (k ~/ cols) * (cell + gap));
  }
  return img.encodePng(d);
}

Uint8List blendRun(List<Uint8List> files, Vals v) {
  final a = _dec(files[0]);
  final b = img.copyResize(_dec(files[1]), width: a.width, height: a.height);
  final m = v['m']!.round();
  final t = v['a']!;
  final out = img.Image(width: a.width, height: a.height, numChannels: 4);
  double mix(double x, double y) {
    final base = switch (m) {
      0 => y,
      1 => x * y,
      2 => 1 - (1 - x) * (1 - y),
      _ => (x - y).abs(),
    };
    return x * (1 - t) + base * t;
  }
  for (final p in out) {
    final pa = a.getPixel(p.x, p.y);
    final pb = b.getPixel(p.x, p.y);
    p.rNormalized = mix(pa.rNormalized.toDouble(), pb.rNormalized.toDouble());
    p.gNormalized = mix(pa.gNormalized.toDouble(), pb.gNormalized.toDouble());
    p.bNormalized = mix(pa.bNormalized.toDouble(), pb.bNormalized.toDouble());
    p.aNormalized = 1.0;
  }
  return img.encodePng(out);
}

Future<Uint8List> pdfRun(List<Uint8List> files, Vals v) async {
  final doc = pw.Document();
  for (final b in files) {
    // normalise everything to JPG/PNG the pdf package can embed
    final i = _dec(b);
    final bytes = i.hasAlpha ? img.encodePng(i) : img.encodeJpg(i, quality: 92);
    final m = pw.MemoryImage(bytes);
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.Center(child: pw.Image(m, fit: pw.BoxFit.contain))));
  }
  return Uint8List.fromList(await doc.save());
}

class MultiImageTool extends StatefulWidget {
  final MultiMode mode;
  const MultiImageTool({super.key, required this.mode});
  @override
  State<MultiImageTool> createState() => _MultiImageToolState();
}

class _MultiImageToolState extends State<MultiImageTool> {
  final files = <Uint8List>[];
  final names = <String>[];
  Uint8List? out;
  bool busy = false;
  int dir = 0, cols = 0, bm = 0;
  double gap = 0, mix = 0.5;

  Future<void> add() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (r == null) return;
    setState(() {
      for (final f in r.files) {
        if (f.bytes != null) {
          files.add(f.bytes!);
          names.add(f.name);
        }
      }
      out = null;
    });
  }

  Future<void> apply() async {
    if (files.length < (widget.mode == MultiMode.pdf ? 1 : 2)) return;
    setState(() => busy = true);
    final list = List<Uint8List>.of(files);
    final vals = <String, double>{'d': dir.toDouble(), 'g': gap, 'c': cols.toDouble(), 'm': bm.toDouble(), 'a': mix};
    final mode = widget.mode;
    try {
      final r = await runMultiIso(mode.index, list, vals);
      if (mounted) setState(() => out = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final o = out;
    if (o == null) return;
    final pdf = widget.mode == MultiMode.pdf;
    final p = await saveBytes(pdf ? 'images.pdf' : '${widget.mode.name}.png', o);
    if (p != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

  List<Widget> extraControls() {
    Widget seg(List<(String, String)> items, int sel, ValueChanged<int> f) =>
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < items.length; i++)
              ButtonSegment(value: i, label: Text(t(context, items[i].$1, items[i].$2)))
          ],
          selected: {sel},
          onSelectionChanged: (s) => setState(() => f(s.first)),
        );
    Widget gapSlider() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t(context, 'المسافة بين الصور', 'Gap')}: ${gap.round()}'),
          Slider(value: gap, min: 0, max: 80, divisions: 16, onChanged: (x) => setState(() => gap = x)),
        ]);
    switch (widget.mode) {
      case MultiMode.pdf:
        return [];
      case MultiMode.merge:
        return [
          const SizedBox(height: 12),
          seg(const [('عمودي', 'Vertical'), ('أفقي', 'Horizontal')], dir, (i) => dir = i),
          gapSlider(),
        ];
      case MultiMode.collage:
        return [
          const SizedBox(height: 12),
          seg(const [('عمودان', '2 columns'), ('3 أعمدة', '3 columns')], cols, (i) => cols = i),
          gapSlider(),
        ];
      case MultiMode.blend:
        return [
          const SizedBox(height: 12),
          Text(t(context, 'تُمزج أول صورتين في القائمة', 'The first two images are blended')),
          const SizedBox(height: 8),
          seg(const [('دمج', 'Mix'), ('ضرب', 'Multiply'), ('شاشة', 'Screen'), ('فرق', 'Difference')], bm, (i) => bm = i),
          Text('${t(context, 'قوة المزج', 'Amount')}: ${mix.toStringAsFixed(2)}'),
          Slider(value: mix, min: 0, max: 1, onChanged: (x) => setState(() => mix = x)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdf = widget.mode == MultiMode.pdf;
    final cs = Theme.of(context).colorScheme;
    final list = Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14)),
      child: files.isEmpty
          ? Center(child: Text(t(context, 'أضف صورًا للبدء', 'Add images to start')))
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: files.length,
              onReorder: (a, b) => setState(() {
                if (b > a) b--;
                files.insert(b, files.removeAt(a));
                names.insert(b, names.removeAt(a));
                out = null;
              }),
              itemBuilder: (_, i) => ListTile(
                key: ValueKey('$i-${names[i]}'),
                leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(files[i],
                        width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 96)),
                title: Text(names[i], overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                          files.removeAt(i);
                          names.removeAt(i);
                          out = null;
                        })),
              ),
            ),
    );
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
            onPressed: add,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(t(context, 'إضافة صور', 'Add images'))),
        ...extraControls(),
        const SizedBox(height: 8),
        FilledButton(
            onPressed: busy ? null : apply,
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(switch (widget.mode) {
                    MultiMode.pdf => t(context, 'إنشاء PDF', 'Create PDF'),
                    MultiMode.merge => t(context, 'دمج', 'Merge'),
                    MultiMode.collage => t(context, 'إنشاء كولاج', 'Make collage'),
                    MultiMode.blend => t(context, 'مزج', 'Blend'),
                  })),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: out == null ? null : save,
            icon: const Icon(Icons.save_alt),
            label: Text(t(context, 'حفظ', 'Save'))),
        if (out != null && pdf)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t(context, 'ملف PDF جاهز للحفظ', 'PDF ready to save'))),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 800) {
          return Row(children: [
            SizedBox(width: 320, child: SingleChildScrollView(child: panel)),
            const SizedBox(width: 16),
            Expanded(child: list),
          ]);
        }
        return Column(children: [
          Expanded(child: list),
          const SizedBox(height: 12),
          panel,
        ]);
      }),
    );
  }
}
