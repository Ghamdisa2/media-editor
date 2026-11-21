import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'art.dart';
import 'pane.dart';
import 'strings.dart';

typedef V = Map<String, Object>;

extension VX on Map<String, Object> {
  double d(String k) => (this[k] as num).toDouble();
  int i(String k) => (this[k] as num).round();
  String s(String k) => this[k] as String;
}

// ---------- FFmpeg engine ----------
Future<void> runFfmpeg(List<String> args, String out) async {
  final all = ['-y', '-hide_banner', '-nostdin', ...args, out];
  if (Platform.isWindows) {
    final local = '${File(Platform.resolvedExecutable).parent.path}\\ffmpeg.exe';
    final bin = File(local).existsSync() ? local : 'ffmpeg';
    final r = await Process.run(bin, all);
    if (r.exitCode != 0) throw _tail('${r.stderr}');
  } else {
    final s = await FFmpegKit.executeWithArguments(all);
    final rc = await s.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) throw _tail(await s.getAllLogsAsString() ?? '');
  }
}

String _tail(String log) {
  final lines = log.split('\n').where((e) => e.trim().isNotEmpty).toList();
  return lines.skip(lines.length > 6 ? lines.length - 6 : 0).join('\n');
}

String _ext(String path) => path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : 'mp4';
String _f(double x) => x.toStringAsFixed(5);
String _sec(double x) => x.toStringAsFixed(3);

const _enc = [
  '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
  '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k'
];
const _encHQ = [
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '16',
  '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k'
];

List<String> _atempo(double s) {
  if (s > 2) return ['atempo=2', 'atempo=${s / 2}'];
  if (s < 0.5) return ['atempo=0.5', 'atempo=${s / 0.5}'];
  return ['atempo=$s'];
}

// ---------- option model ----------
enum FK { slider, choice, text }

class FOpt {
  final String key, ar, en;
  final FK kind;
  final double min, max, def;
  final int? div;
  final List<(String, String)> choices;
  final String text;
  const FOpt.slider(this.key, this.ar, this.en, this.min, this.max, this.def, {this.div})
      : kind = FK.slider, choices = const [], text = '';
  const FOpt.choice(this.key, this.ar, this.en, this.choices)
      : kind = FK.choice, min = 0, max = 0, def = 0, div = null, text = '';
  const FOpt.text(this.key, this.ar, this.en, this.text)
      : kind = FK.text, min = 0, max = 0, def = 0, div = null, choices = const [];
}

enum Sel { none, crop, region, range, text, logo }

class Ctx {
  final List<String> ins;
  final V v;
  final Directory tmp;
  final Rect rect;
  final double start, end, dur;
  final Size vsize;
  final Offset pos;
  final List<double> vols;
  final String? img;
  final Future<String> Function(double refW) overlay;
  Ctx(this.ins, this.v, this.tmp, this.rect, this.start, this.end, this.dur,
      this.vsize, this.pos, this.vols, this.img, this.overlay);
  bool get trimmed => start > 0.05 || (end > 0 && end < dur - 0.05);
  List<int> px() {
    if (vsize.width <= 0) throw 'تعذر قراءة أبعاد الفيديو / Cannot read video size';
    int e(double x) => (x ~/ 2) * 2;
    return [
      e(rect.left * vsize.width).toInt(), e(rect.top * vsize.height).toInt(),
      math.max(2, e(rect.width * vsize.width)).toInt(), math.max(2, e(rect.height * vsize.height)).toInt()
    ];
  }
}

typedef Build = Future<List<String>> Function(Ctx c);

class FfmpegTool extends StatefulWidget {
  final FileType type;
  final bool multi, audio, preview, wave, perVol, needsLogo;
  final Sel sel;
  final List<FOpt> opts;
  final Build build;
  final String Function(List<String> ins, V v) ext;
  const FfmpegTool({
    super.key,
    required this.type,
    required this.opts,
    required this.build,
    required this.ext,
    this.sel = Sel.none,
    this.multi = false,
    this.audio = false,
    this.preview = true,
    this.wave = false,
    this.perVol = false,
    this.needsLogo = false,
  });
  @override
  State<FfmpegTool> createState() => _FfmpegToolState();
}

class _FfmpegToolState extends State<FfmpegTool> {
  final ins = <String>[];
  final names = <String>[];
  final vols = <double>[];
  final pane = Pane();
  String? orig, result, outExt, error, wavePng, logoPath;
  Uint8List? logoBytes;
  ui.Image? logoUi;
  bool showResult = false, busy = false;
  Rect rect = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  int aspectIdx = 0;
  double rs = 0, re = 0, lastDur = -1;
  Offset pos = const Offset(0.5, 0.5);
  double logoSize = 20, logoOp = 1, logoRot = 0;
  final spec = TextSpec();
  static const aspects = <double?>[null, 1, 16 / 9, 9 / 16, 4 / 3, 3 / 4];

  late final V v = {
    for (final o in widget.opts)
      o.key: o.kind == FK.text ? o.text : (o.kind == FK.slider ? o.def : 0)
  };
  late final ctrls = {
    for (final o in widget.opts)
      if (o.kind == FK.text) o.key: TextEditingController(text: o.text)
  };

  @override
  void initState() {
    super.initState();
    pane.addListener(_onPane);
  }

  void _onPane() {
    if (showResult) return;
    if (pane.vsize.width > 0) origV = pane.vsize;
    final d = pane.seconds;
    if (d > 0 && d != lastDur) {
      lastDur = d;
      setState(() {
        rs = 0;
        re = d;
      });
    }
  }

  @override
  void dispose() {
    pane.removeListener(_onPane);
    pane.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: widget.type, allowMultiple: widget.multi);
    if (r == null) return;
    setState(() {
      if (!widget.multi) {
        ins.clear();
        names.clear();
        vols.clear();
      }
      for (final f in r.files) {
        if (f.path != null) {
          ins.add(f.path!);
          names.add(f.name);
          vols.add(1);
        }
      }
      result = null;
      showResult = false;
      error = null;
      wavePng = null;
    });
    if (ins.isEmpty) return;
    orig = widget.multi ? ins.first : ins.last;
    lastDur = -1;
    await pane.open(orig!);
    if (widget.wave && !widget.multi) _makeWave(orig!);
  }

  Future<void> _makeWave(String p) async {
    try {
      final dir = await Directory.systemTemp.createTemp('me_w');
      final o = '${dir.path}${Platform.pathSeparator}wave.png';
      await runFfmpeg(['-i', p, '-filter_complex', 'showwavespic=s=1400x140:colors=0x0E7C86', '-frames:v', '1'], o);
      if (mounted) setState(() => wavePng = o);
    } catch (_) {}
  }

  Future<void> pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f?.bytes == null) return;
    final u = await decodeUi(f!.bytes!);
    setState(() {
      logoBytes = f.bytes;
      logoPath = f.path;
      logoUi = u;
    });
  }

  Group group(double refW) {
    if (widget.sel == Sel.logo) {
      return Group(logo: logoUi, lw: refW * logoSize / 100, op: logoOp, rot: logoRot);
    }
    return Group(art: TextArt(spec, refW * spec.size / 100));
  }

  Future<String> overlayPng(double refW, Directory tmp) async {
    final g = group(refW);
    final png = await renderPng(g.size, (c) => g.paint(c));
    final f = File('${tmp.path}${Platform.pathSeparator}overlay.png');
    await f.writeAsBytes(png);
    return f.path;
  }

  Future<void> run(bool preview) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      for (final e in ctrls.entries) {
        v[e.key] = e.value.text;
      }
      final dir = await Directory.systemTemp.createTemp('me_');
      final e = widget.ext(ins, v);
      final o = '${dir.path}${Platform.pathSeparator}out.$e';
      final ctx = Ctx(List.of(ins), v, dir, rect, rs, re, lastDur > 0 ? lastDur : pane.seconds,
          origV, pos, List.of(vols), logoPath, (w) => overlayPng(w, dir));
      var args = await widget.build(ctx);
      if (preview) args = [...args, '-t', '5'];
      await runFfmpeg(args, o);
      result = o;
      outExt = e;
      showResult = true;
      await pane.open(o);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Size origV = Size.zero;

  Future<void> toggle(bool res) async {
    if (res == showResult) return;
    setState(() => showResult = res);
    await pane.open(res ? result! : orig!);
  }

  Future<void> save() async {
    final o = result;
    if (o == null) return;
    final n = names.first;
    final base = n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;
    final fn = '${base}_edited.$outExt';
    String? p;
    if (Platform.isAndroid || Platform.isIOS) {
      p = await FilePicker.platform.saveFile(fileName: fn, bytes: await File(o).readAsBytes());
    } else {
      p = await FilePicker.platform.saveFile(fileName: fn);
      if (p != null) await File(o).copy(p);
    }
    if (p != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

  // ---------- UI pieces ----------
  Widget control(FOpt o) {
    final label = t(context, o.ar, o.en);
    switch (o.kind) {
      case FK.choice:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < o.choices.length; i++)
              ChoiceChip(
                  label: Text(t(context, o.choices[i].$1, o.choices[i].$2)),
                  selected: v[o.key] == i,
                  onSelected: (_) => setState(() => v[o.key] = i)),
          ]),
        ]);
      case FK.slider:
        final x = (v[o.key] as num).toDouble();
        return labeledSlider(label, x, o.min, o.max, (n) => setState(() => v[o.key] = n), div: o.div);
      case FK.text:
        return TextField(
            controller: ctrls[o.key],
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));
    }
  }

  Rect _fitAspect(double a) {
    final vs = pane.vsize;
    final vr = vs.height > 0 ? vs.width / vs.height : 16 / 9;
    var fw = 0.8;
    var fh = fw * vr / a;
    if (fh > 0.9) {
      fh = 0.9;
      fw = fh * a / vr;
    }
    return Rect.fromCenter(center: const Offset(0.5, 0.5), width: fw, height: fh);
  }

  Widget _drag(Size S, Size item, Widget child) => Positioned(
        left: pos.dx * S.width - item.width / 2,
        top: pos.dy * S.height - item.height / 2,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => pos = Offset(
              (pos.dx + d.delta.dx / S.width).clamp(0.0, 1.0).toDouble(),
              (pos.dy + d.delta.dy / S.height).clamp(0.0, 1.0).toDouble())),
          child: child,
        ),
      );

  Widget? overlay(Size S) {
    if (showResult || orig == null) return null;
    switch (widget.sel) {
      case Sel.crop:
        return RectEditor(rect: rect, aspect: aspects[aspectIdx], onChanged: (r) => setState(() => rect = r));
      case Sel.region:
        return RectEditor(rect: rect, ellipse: v['s'] == 1, onChanged: (r) => setState(() => rect = r));
      case Sel.text:
        if (spec.text.trim().isEmpty) return null;
        final g = group(S.width);
        return _drag(S, g.size, CustomPaint(size: g.size, painter: GroupPainter(g)));
      case Sel.logo:
        if (logoUi == null) return null;
        final g = group(S.width);
        return _drag(S, g.size, CustomPaint(size: g.size, painter: GroupPainter(g)));
      default:
        return null;
    }
  }

  Widget rangeBar() {
    final d = math.max(pane.seconds, 0.1);
    return Column(children: [
      RangeSlider(
        values: RangeValues(rs.clamp(0, d).toDouble(), (re <= 0 ? d : re).clamp(0, d).toDouble()),
        min: 0,
        max: d,
        onChanged: (r) {
          final startMoved = (r.start - rs).abs() > (r.end - re).abs();
          setState(() {
            rs = r.start;
            re = r.end;
          });
          pane.seekTo(startMoved ? r.start : r.end);
        },
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${t(context, 'من', 'From')} ${fmt(rs)}'),
        Text('${t(context, 'المدة', 'Length')} ${fmt((re <= 0 ? d : re) - rs)}'),
        Text('${t(context, 'إلى', 'To')} ${fmt(re <= 0 ? d : re)}'),
      ]),
    ]);
  }

  Widget multiList() => SizedBox(
        height: 190,
        child: ReorderableListView.builder(
          buildDefaultDragHandles: true,
          itemCount: ins.length,
          onReorder: (a, b) => setState(() {
            if (b > a) b--;
            ins.insert(b, ins.removeAt(a));
            names.insert(b, names.removeAt(a));
            vols.insert(b, vols.removeAt(a));
            result = null;
          }),
          itemBuilder: (_, i) => ListTile(
            key: ValueKey('$i-${names[i]}'),
            dense: true,
            leading: Text('${i + 1}'),
            title: widget.perVol
                ? Row(children: [
                    Expanded(flex: 2, child: Text(names[i], overflow: TextOverflow.ellipsis)),
                    Expanded(
                        flex: 3,
                        child: Slider(
                            value: vols[i],
                            min: 0,
                            max: 3,
                            onChanged: (x) => setState(() => vols[i] = x))),
                    Text('${(vols[i] * 100).round()}%'),
                  ])
                : Text(names[i], overflow: TextOverflow.ellipsis),
            trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                      ins.removeAt(i);
                      names.removeAt(i);
                      vols.removeAt(i);
                    })),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final need = widget.multi ? 2 : 1;
    final ready = ins.length >= need && (!widget.needsLogo || logoUi != null);
    final hasMedia = orig != null;

    final panel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.tonalIcon(
          onPressed: pick,
          icon: const Icon(Icons.folder_open),
          label: Text(widget.multi ? t(context, 'إضافة ملفات', 'Add files') : t(context, 'اختيار ملف', 'Choose file'))),
      if (widget.needsLogo) ...[
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
            onPressed: pickLogo,
            icon: const Icon(Icons.image_outlined),
            label: Text(t(context, 'اختيار صورة العلامة', 'Choose watermark image'))),
        labeledSlider(t(context, 'حجم العلامة %', 'Size %'), logoSize, 3, 80, (x) => setState(() => logoSize = x)),
        labeledSlider(t(context, 'التدوير', 'Rotation'), logoRot, -180, 180, (x) => setState(() => logoRot = x.roundToDouble())),
        labeledSlider(t(context, 'الشفافية', 'Opacity'), logoOp, 0.1, 1, (x) => setState(() => logoOp = x)),
        Text(t(context, 'اسحب العلامة على الفيديو لتحديد مكانها', 'Drag the watermark on the video to place it'),
            style: TextStyle(color: cs.outline, fontSize: 12)),
      ],
      const SizedBox(height: 12),
      if (widget.sel == Sel.crop) ...[
        Text(t(context, 'نسبة القص', 'Crop ratio')),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < aspects.length; i++)
            ChoiceChip(
                label: Text(i == 0 ? t(context, 'حر', 'Free') : ['', '1:1', '16:9', '9:16', '4:3', '3:4'][i]),
                selected: aspectIdx == i,
                onSelected: (_) => setState(() {
                      aspectIdx = i;
                      if (aspects[i] != null) rect = _fitAspect(aspects[i]!);
                    })),
        ]),
        const SizedBox(height: 12),
      ],
      if (widget.sel == Sel.text) ...[
        TextEditorPanel(s: spec, onChanged: () => setState(() {})),
        Text(t(context, 'اسحب النص على الفيديو لتحديد مكانه', 'Drag the text on the video to place it'),
            style: TextStyle(color: cs.outline, fontSize: 12)),
        const SizedBox(height: 12),
      ],
      for (final o in widget.opts) ...[control(o), const SizedBox(height: 12)],
      Row(children: [
        if (widget.preview)
          Expanded(
              child: OutlinedButton(
                  onPressed: ready && !busy ? () => run(true) : null,
                  child: Text(t(context, 'معاينة 5 ثوان', 'Preview 5s')))),
        if (widget.preview) const SizedBox(width: 8),
        Expanded(
            child: FilledButton(
                onPressed: ready && !busy ? () => run(false) : null,
                child: Text(t(context, 'تنفيذ كامل', 'Run full')))),
      ]),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: result == null || busy ? null : save,
          icon: const Icon(Icons.save_alt),
          label: Text(t(context, 'اعتماد وحفظ', 'Approve & save'))),
      if (busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
        const SizedBox(height: 4),
        Text(t(context, 'جاري المعالجة...', 'Processing...')),
      ],
      if (result != null && !busy)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                '${t(context, 'تمت المعالجة', 'Done')} - ${(File(result!).lengthSync() / 1048576).toStringAsFixed(2)} MB',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600))),
      if (error != null)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(error!, style: TextStyle(color: cs.error))),
    ]);

    final right = Column(children: [
      if (result != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(label: Text(t(context, 'الأصلي', 'Original')), selected: !showResult, onSelected: (_) => toggle(false)),
            ChoiceChip(label: Text(t(context, 'النتيجة', 'Result')), selected: showResult, onSelected: (_) => toggle(true)),
          ]),
        ),
      Expanded(
          child: MediaPane(
              pane: pane,
              hasMedia: hasMedia,
              audio: widget.audio,
              overlay: (S) => overlay(S) ?? const SizedBox.shrink())),
      if (widget.wave && hasMedia) ...[
        const SizedBox(height: 8),
        WaveBox(png: wavePng, pane: pane, start: rs, end: re),
      ],
      if (widget.sel == Sel.range && hasMedia && !showResult) rangeBar(),
      if (widget.multi && ins.isNotEmpty) multiList(),
    ]);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 800) {
          return Row(children: [
            SizedBox(width: 360, child: SingleChildScrollView(child: panel)),
            const SizedBox(width: 16),
            Expanded(child: right),
          ]);
        }
        return Column(children: [
          Expanded(flex: 5, child: right),
          const SizedBox(height: 8),
          Expanded(flex: 4, child: SingleChildScrollView(child: panel)),
        ]);
      }),
    );
  }
}

// ---------- tool definitions ----------
const _vt = FileType.video;
const _at = FileType.audio;
String _mp4(List<String> i, V v) => 'mp4';
String _sameExt(List<String> i, V v) => _ext(i.first);
String _mp3(List<String> i, V v) => 'mp3';
List<(String, String)> _c(List<String> xs) => [for (final x in xs) (x, x)];

Widget? ffmpegTool(String id) {
  switch (id) {
    case 'v_crop':
      return FfmpegTool(
        type: _vt, sel: Sel.crop, opts: const [], ext: _mp4,
        build: (c) async {
          final p = c.px();
          return ['-i', c.ins[0], '-vf', 'crop=${p[2]}:${p[3]}:${p[0]}:${p[1]}', ..._enc];
        },
      );
    case 'v_blur':
      return FfmpegTool(
        type: _vt, sel: Sel.region, ext: _mp4,
        opts: const [
          FOpt.choice('m', 'النطاق', 'Scope', [('منطقة محددة', 'Selected area'), ('كامل الفيديو', 'Whole video')]),
          FOpt.choice('s', 'شكل البقعة', 'Spot shape', [('مستطيل', 'Rectangle'), ('بيضاوي', 'Ellipse')]),
          FOpt.slider('r', 'قوة التمويه', 'Blur strength', 2, 40, 14, div: 38),
        ],
        build: (c) async {
          if (c.v.i('m') == 1) return ['-i', c.ins[0], '-vf', 'boxblur=${c.v.i('r')}:2', ..._enc];
          final p = c.px();
          final r = math.max(1, math.min(c.v.i('r'), math.min(p[2], p[3]) ~/ 2 - 1));
          final head = '[0:v]split[a][b];[b]crop=${p[2]}:${p[3]}:${p[0]}:${p[1]},boxblur=$r:2';
          if (c.v.i('s') == 0) {
            return ['-i', c.ins[0], '-filter_complex', '$head[c];[a][c]overlay=${p[0]}:${p[1]}', ..._enc];
          }
          return [
            '-i', c.ins[0], '-filter_complex',
            "$head,split[c1][c2];[c2]geq=lum='255*lte(pow((2*X-W)/W,2)+pow((2*Y-H)/H,2),1)':cb=128:cr=128[m];[c1][m]alphamerge[cc];[a][cc]overlay=${p[0]}:${p[1]}",
            ..._enc
          ];
        },
      );
    case 'v_trim':
      return FfmpegTool(
        type: _vt, sel: Sel.range, preview: false, opts: const [], ext: _mp4,
        build: (c) async => ['-ss', _sec(c.start), '-to', _sec(c.end), '-i', c.ins[0], ..._enc],
      );
    case 'v_enhance':
      return FfmpegTool(
        type: _vt, ext: _mp4,
        opts: const [
          FOpt.choice('p', 'النمط', 'Style', [('طبيعي', 'Natural'), ('حيوي', 'Vivid'), ('سينمائي', 'Cinematic'), ('حاد', 'Sharp')]),
          FOpt.choice('u', 'رفع الدقة', 'Upscale', [('بدون', 'None'), ('×1.5', '×1.5'), ('×2', '×2')]),
          FOpt.slider('n', 'إزالة التشويش', 'Denoise', 0, 6, 2, div: 6),
        ],
        build: (c) async {
          const presets = [
            'eq=contrast=1.06:saturation=1.12:brightness=0.01',
            'eq=contrast=1.12:saturation=1.35:gamma=1.03',
            'eq=contrast=1.15:saturation=0.92,colorbalance=rs=0.04:bs=-0.04:rh=-0.03:bh=0.05',
            'eq=contrast=1.05:saturation=1.05'
          ];
          final p = c.v.i('p');
          final sharp = [0.8, 0.9, 0.6, 1.6][p];
          final up = [1.0, 1.5, 2.0][c.v.i('u')];
          final dn = c.v.i('n');
          final vf = [
            if (dn > 0) 'hqdn3d=$dn:$dn:${dn * 2}:${dn * 2}',
            if (up > 1) 'scale=trunc(iw*$up/2)*2:trunc(ih*$up/2)*2:flags=lanczos',
            presets[p],
            'unsharp=7:7:$sharp',
          ].join(',');
          return ['-i', c.ins[0], '-vf', vf, ..._encHQ];
        },
      );
    case 'v_merge':
      return FfmpegTool(
        type: _vt, multi: true, preview: false, opts: const [], ext: _mp4,
        build: (c) async {
          final n = c.ins.length;
          final f = StringBuffer();
          for (var i = 0; i < n; i++) {
            f.write('[$i:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v$i];');
            f.write('[$i:a]aformat=sample_rates=44100:channel_layouts=stereo[a$i];');
          }
          for (var i = 0; i < n; i++) {
            f.write('[v$i][a$i]');
          }
          f.write('concat=n=$n:v=1:a=1[v][a]');
          return [for (final i in c.ins) ...['-i', i], '-filter_complex', f.toString(), '-map', '[v]', '-map', '[a]', ..._enc];
        },
      );
    case 'v_mp3':
      return FfmpegTool(
        type: _vt, sel: Sel.range, preview: false, opts: const [], ext: _mp3,
        build: (c) async => [
          if (c.trimmed) ...['-ss', _sec(c.start), '-to', _sec(c.end)],
          '-i', c.ins[0], '-vn', '-c:a', 'libmp3lame', '-q:a', '2'
        ],
      );
    case 'v_flip':
      return FfmpegTool(
        type: _vt, ext: _mp4,
        opts: const [
          FOpt.choice('m', 'الإجراء', 'Action', [
            ('قلب أفقي', 'Flip horizontal'), ('قلب عمودي', 'Flip vertical'),
            ('تدوير 90°', 'Rotate 90°'), ('تدوير 180°', 'Rotate 180°')
          ]),
        ],
        build: (c) async =>
            ['-i', c.ins[0], '-vf', ['hflip', 'vflip', 'transpose=1', 'hflip,vflip'][c.v.i('m')], ..._enc],
      );
    case 'v_speed':
      return FfmpegTool(
        type: _vt, ext: _mp4,
        opts: const [FOpt.slider('s', 'السرعة', 'Speed', 0.25, 4, 2, div: 15)],
        build: (c) async {
          final s = c.v.d('s');
          return ['-i', c.ins[0], '-vf', 'setpts=PTS/$s', '-af', _atempo(s).join(','), ..._enc];
        },
      );
    case 'v_frame':
      return FfmpegTool(
        type: _vt, ext: _mp4,
        opts: const [
          FOpt.choice('a', 'الإطار', 'Frame', [('16:9', '16:9'), ('9:16', '9:16'), ('1:1', '1:1'), ('4:5', '4:5')]),
          FOpt.choice('m', 'الخلفية', 'Background', [('أسود', 'Black'), ('تمويه', 'Blurred')]),
        ],
        build: (c) async {
          final sz = [(1920, 1080), (1080, 1920), (1080, 1080), (1080, 1350)][c.v.i('a')];
          final w = sz.$1, h = sz.$2;
          if (c.v.i('m') == 0) {
            return ['-i', c.ins[0], '-vf', 'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1', ..._enc];
          }
          return [
            '-i', c.ins[0], '-filter_complex',
            '[0:v]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,boxblur=20:5[bg];[0:v]scale=$w:$h:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2,setsar=1',
            ..._enc
          ];
        },
      );
    case 'v_convert':
      const fm = ['mp4', 'mkv', 'webm', 'avi', 'mov', 'gif'];
      return FfmpegTool(
        type: _vt, preview: false,
        opts: [FOpt.choice('f', 'الصيغة', 'Format', _c(['MP4', 'MKV', 'WEBM', 'AVI', 'MOV', 'GIF']))],
        ext: (i, v) => fm[v.i('f')],
        build: (c) async {
          switch (fm[c.v.i('f')]) {
            case 'webm':
              return ['-i', c.ins[0], '-c:v', 'libvpx-vp9', '-crf', '32', '-b:v', '0', '-c:a', 'libopus'];
            case 'avi':
              return ['-i', c.ins[0], '-c:v', 'mpeg4', '-q:v', '4', '-c:a', 'libmp3lame'];
            case 'gif':
              return ['-i', c.ins[0], '-vf', 'fps=12,scale=480:-1:flags=lanczos', '-an'];
            default:
              return ['-i', c.ins[0], ..._enc];
          }
        },
      );
    case 'v_compress':
      return FfmpegTool(
        type: _vt, preview: false, ext: _mp4,
        opts: const [
          FOpt.slider('q', 'مستوى الضغط (أعلى = أصغر)', 'Compression (higher = smaller)', 18, 38, 28, div: 20),
          FOpt.choice('h', 'الارتفاع', 'Height', [('الأصلي', 'Original'), ('1080', '1080'), ('720', '720'), ('480', '480')]),
        ],
        build: (c) async {
          final h = [0, 1080, 720, 480][c.v.i('h')];
          return [
            '-i', c.ins[0],
            if (h > 0) ...['-vf', 'scale=-2:$h'],
            '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '${c.v.i('q')}',
            '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k'
          ];
        },
      );
    case 'v_text':
      return FfmpegTool(
        type: _vt, sel: Sel.text, opts: const [], ext: _mp4,
        build: (c) async {
          final w = c.vsize.width > 0 ? c.vsize.width : 1280.0;
          final png = await c.overlay(w);
          return [
            '-i', c.ins[0], '-i', png, '-filter_complex',
            "[0:v][1:v]overlay=x='main_w*${_f(c.pos.dx)}-overlay_w/2':y='main_h*${_f(c.pos.dy)}-overlay_h/2'",
            ..._enc
          ];
        },
      );
    case 'v_wm_add':
      return FfmpegTool(
        type: _vt, sel: Sel.logo, needsLogo: true, opts: const [], ext: _mp4,
        build: (c) async {
          final w = c.vsize.width > 0 ? c.vsize.width : 1280.0;
          final png = await c.overlay(w);
          return [
            '-i', c.ins[0], '-i', png, '-filter_complex',
            "[0:v][1:v]overlay=x='main_w*${_f(c.pos.dx)}-overlay_w/2':y='main_h*${_f(c.pos.dy)}-overlay_h/2'",
            ..._enc
          ];
        },
      );
    case 'v_wm_remove':
      return FfmpegTool(
        type: _vt, sel: Sel.region, ext: _mp4,
        opts: const [
          FOpt.choice('k', 'الطريقة', 'Method', [('إزالة ذكية', 'Smart removal'), ('تمويه', 'Blur')]),
          FOpt.choice('s', 'شكل المنطقة', 'Area shape', [('مستطيل', 'Rectangle'), ('بيضاوي', 'Ellipse')]),
        ],
        build: (c) async {
          final p = c.px();
          if (c.v.i('k') == 0) {
            final vw = c.vsize.width.toInt(), vh = c.vsize.height.toInt();
            final x = math.max(1, p[0]), y = math.max(1, p[1]);
            final w = math.min(p[2], vw - x - 1), h = math.min(p[3], vh - y - 1);
            return ['-i', c.ins[0], '-vf', 'delogo=x=$x:y=$y:w=$w:h=$h', ..._enc];
          }
          final r = math.max(1, math.min(12, math.min(p[2], p[3]) ~/ 2 - 1));
          final head = '[0:v]split[a][b];[b]crop=${p[2]}:${p[3]}:${p[0]}:${p[1]},boxblur=$r:3';
          if (c.v.i('s') == 0) {
            return ['-i', c.ins[0], '-filter_complex', '$head[c];[a][c]overlay=${p[0]}:${p[1]}', ..._enc];
          }
          return [
            '-i', c.ins[0], '-filter_complex',
            "$head,split[c1][c2];[c2]geq=lum='255*lte(pow((2*X-W)/W,2)+pow((2*Y-H)/H,2),1)':cb=128:cr=128[m];[c1][m]alphamerge[cc];[a][cc]overlay=${p[0]}:${p[1]}",
            ..._enc
          ];
        },
      );
    // ---------------- audio ----------------
    case 'a_merge':
      return FfmpegTool(
        type: _at, audio: true, multi: true, preview: false, opts: const [], ext: _mp3,
        build: (c) async => [
          for (final i in c.ins) ...['-i', i],
          '-filter_complex', '${List.generate(c.ins.length, (i) => '[$i:a]').join()}concat=n=${c.ins.length}:v=0:a=1[a]',
          '-map', '[a]', '-c:a', 'libmp3lame', '-q:a', '2'
        ],
      );
    case 'a_mix':
      return FfmpegTool(
        type: _at, audio: true, multi: true, perVol: true, preview: false, opts: const [], ext: _mp3,
        build: (c) async {
          final n = c.ins.length;
          final f = StringBuffer();
          for (var i = 0; i < n; i++) {
            f.write('[$i:a]volume=${c.vols[i].toStringAsFixed(2)}[a$i];');
          }
          for (var i = 0; i < n; i++) {
            f.write('[a$i]');
          }
          f.write('amix=inputs=$n:duration=longest:dropout_transition=0,volume=$n,alimiter=limit=0.95[a]');
          return [for (final i in c.ins) ...['-i', i], '-filter_complex', f.toString(), '-map', '[a]', '-c:a', 'libmp3lame', '-q:a', '2'];
        },
      );
    case 'a_trim':
      return FfmpegTool(
        type: _at, audio: true, wave: true, sel: Sel.range, preview: false, opts: const [], ext: _sameExt,
        build: (c) async => ['-ss', _sec(c.start), '-to', _sec(c.end), '-i', c.ins[0]],
      );
    case 'a_speed':
      return FfmpegTool(
        type: _at, audio: true, wave: true, ext: _sameExt,
        opts: const [FOpt.slider('s', 'السرعة', 'Speed', 0.25, 4, 1.5, div: 15)],
        build: (c) async => ['-i', c.ins[0], '-af', _atempo(c.v.d('s')).join(',')],
      );
    case 'a_convert':
      const af = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wma', 'mp2', 'mpeg', 'aiff'];
      return FfmpegTool(
        type: _at, audio: true, preview: false,
        opts: [FOpt.choice('f', 'الصيغة', 'Format', _c(af.map((e) => e.toUpperCase()).toList()))],
        ext: (i, v) => af[v.i('f')],
        build: (c) async {
          final codec = switch (af[c.v.i('f')]) {
            'mp3' => ['-c:a', 'libmp3lame', '-q:a', '2'],
            'm4a' => ['-c:a', 'aac', '-b:a', '192k'],
            'aac' => ['-c:a', 'aac', '-b:a', '192k', '-f', 'adts'],
            'opus' => ['-c:a', 'libopus', '-b:a', '128k'],
            'wma' => ['-c:a', 'wmav2', '-b:a', '192k'],
            'mp2' => ['-c:a', 'mp2', '-b:a', '192k'],
            'mpeg' => ['-c:a', 'mp2', '-b:a', '192k', '-f', 'mp2'],
            _ => <String>[],
          };
          return ['-i', c.ins[0], '-vn', ...codec];
        },
      );
    case 'a_enhance':
      return FfmpegTool(
        type: _at, audio: true, ext: _mp3,
        opts: const [
          FOpt.choice('m', 'النوع', 'Type', [('كلام / تسجيل صوتي', 'Speech / voice'), ('موسيقى', 'Music')]),
          FOpt.choice('n', 'قوة إزالة الضجيج', 'Noise reduction', [('خفيفة', 'Light'), ('متوسطة', 'Medium'), ('قوية', 'Strong')]),
        ],
        build: (c) async {
          final nr = [12, 22, 34][c.v.i('n')];
          final voice = c.v.i('m') == 0;
          final af = voice
              ? 'highpass=f=90,lowpass=f=12000,afftdn=nr=$nr:nf=-35:tn=1,agate=threshold=0.02:ratio=2:attack=10:release=250,equalizer=f=3000:t=q:w=1.2:g=3,acompressor=threshold=-20dB:ratio=3:attack=5:release=80,loudnorm=I=-16:TP=-1.5:LRA=11'
              : 'highpass=f=30,afftdn=nr=${nr ~/ 2}:nf=-40:tn=1,loudnorm=I=-14:TP=-1.0:LRA=12';
          return ['-i', c.ins[0], '-af', af, '-c:a', 'libmp3lame', '-q:a', '2'];
        },
      );
    case 'a_fx':
      return FfmpegTool(
        type: _at, audio: true, ext: _mp3,
        opts: const [
          FOpt.choice('e', 'المؤثر', 'Effect', [
            ('صدى', 'Echo'), ('صدى قاعة', 'Hall reverb'), ('كورس', 'Chorus'), ('تعزيز الجهير', 'Bass boost'),
            ('تعزيز الحدة', 'Treble boost'), ('صوت أرفع', 'Higher pitch'), ('صوت أغلظ', 'Lower pitch'),
            ('مكالمة هاتف', 'Telephone'), ('مكبر صوت', 'Megaphone'), ('رعشة', 'Tremolo'), ('فلانجر', 'Flanger'),
            ('عكس الصوت', 'Reverse'), ('تلاشي دخول', 'Fade in'), ('تلاشي خروج', 'Fade out'),
          ]),
          FOpt.slider('i', 'قوة المؤثر', 'Intensity', 0, 1, 0.5, div: 20),
        ],
        build: (c) async {
          final i = c.v.d('i');
          final e = c.v.i('e');
          String pitch(double f) => 'aresample=44100,asetrate=${(44100 * f).round()},aresample=44100,atempo=${(1 / f).toStringAsFixed(4)}';
          final af = [
            'aecho=0.8:0.88:${(40 + i * 400).round()}:${(0.2 + 0.5 * i).toStringAsFixed(2)}',
            'aecho=0.8:0.9:${(500 + i * 500).round()}|${(900 + i * 800).round()}:0.4|0.3',
            'chorus=0.6:0.9:55|60|45:0.4|0.32|0.3:0.25|0.4|0.3:2|2.3|1.3',
            'bass=g=${(4 + i * 14).round()}:f=100',
            'treble=g=${(4 + i * 12).round()}:f=3500',
            pitch(1 + i * 0.6),
            pitch(1 - i * 0.4),
            'highpass=f=300,lowpass=f=3400,acompressor',
            'highpass=f=600,lowpass=f=4000,volume=1.5,acompressor=threshold=-20dB:ratio=6',
            'tremolo=f=${(4 + i * 8).toStringAsFixed(1)}:d=${(0.4 + 0.5 * i).toStringAsFixed(2)}',
            'flanger=delay=${(5 + i * 10).round()}:depth=${(2 + i * 5).round()}:speed=0.5',
            'areverse',
            'afade=t=in:d=${(1 + i * 4).toStringAsFixed(1)}',
            'areverse,afade=t=in:d=${(1 + i * 4).toStringAsFixed(1)},areverse',
          ][e];
          return ['-i', c.ins[0], '-af', af, '-c:a', 'libmp3lame', '-q:a', '2'];
        },
      );
  }
  return null;
}
