import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:video_player/video_player.dart';
import 'common.dart';
import 'strings.dart';
import 'video_studio.dart' show runFfmpeg, atempo, baseName;

enum AM { merge, mix, trim, speed, convert, enhance, fx }

AM? amFor(String id) => switch (id) {
      'a_merge' => AM.merge,
      'a_mix' => AM.mix,
      'a_trim' => AM.trim,
      'a_speed' => AM.speed,
      'a_convert' => AM.convert,
      'a_enhance' => AM.enhance,
      'a_fx' => AM.fx,
      _ => null,
    };

// (label, ext, codec args)
const formats = <(String, String, List<String>)>[
  ('MP3', 'mp3', ['-c:a', 'libmp3lame', '-q:a', '2']),
  ('WAV', 'wav', []),
  ('M4A', 'm4a', ['-c:a', 'aac', '-b:a', '192k']),
  ('AAC', 'aac', ['-c:a', 'aac', '-b:a', '192k']),
  ('OGG', 'ogg', ['-c:a', 'libvorbis', '-q:a', '5']),
  ('OPUS', 'opus', ['-c:a', 'libopus', '-b:a', '128k']),
  ('FLAC', 'flac', []),
  ('WMA', 'wma', ['-c:a', 'wmav2', '-b:a', '192k']),
  ('MPEG', 'mpeg', ['-c:a', 'mp2', '-b:a', '192k', '-f', 'mp2']),
  ('MP2', 'mp2', ['-c:a', 'mp2', '-b:a', '192k']),
  ('AC3', 'ac3', ['-c:a', 'ac3', '-b:a', '192k']),
  ('AIFF', 'aiff', []),
];

const fxList = <(String, String)>[
  ('صدى', 'Echo'), ('صدى عميق (قاعة)', 'Reverb hall'), ('كورس', 'Chorus'), ('فلانجر', 'Flanger'),
  ('فيزر', 'Phaser'), ('تردد (Tremolo)', 'Tremolo'), ('اهتزاز (Vibrato)', 'Vibrato'),
  ('تعزيز الجهير', 'Bass boost'), ('تعزيز الحاد', 'Treble boost'), ('صوت رفيع (سنجاب)', 'Chipmunk'),
  ('صوت غليظ', 'Deep voice'), ('صوت روبوت', 'Robot'), ('هاتف', 'Telephone'), ('راديو قديم', 'Old radio'),
  ('صوت ثماني الأبعاد', '8D audio'), ('عكس الصوت', 'Reverse'), ('ظهور تدريجي', 'Fade in'), ('اختفاء تدريجي', 'Fade out'),
  ('رفع الصوت', 'Louder'),
];

String fxFilter(int i, double k, double dur) {
  // k = intensity 0..1
  final pitch = (double f) => 'asetrate=44100*$f,aresample=44100,atempo=${(1 / f).toStringAsFixed(4)}';
  switch (i) {
    case 0:
      return 'aecho=0.8:0.88:${(200 + 600 * k).round()}:${(0.2 + 0.4 * k).toStringAsFixed(2)}';
    case 1:
      return 'aecho=0.8:0.85:${(40 + 30 * k).round()}|${(90 + 60 * k).round()}|${(160 + 100 * k).round()}:0.4|0.3|0.2,aecho=0.8:0.9:${(500 + 400 * k).round()}:${(0.2 + 0.2 * k).toStringAsFixed(2)}';
    case 2:
      return 'chorus=0.5:0.9:50|60|40:0.4|0.32|0.3:0.25|0.4|0.3:2|2.3|1.3';
    case 3:
      return 'flanger=delay=${(2 + 8 * k).round()}:depth=${(2 + 8 * k).round()}:speed=0.5';
    case 4:
      return 'aphaser=type=t:speed=${(0.4 + 1.6 * k).toStringAsFixed(2)}';
    case 5:
      return 'tremolo=f=${(3 + 12 * k).toStringAsFixed(1)}:d=${(0.4 + 0.5 * k).toStringAsFixed(2)}';
    case 6:
      return 'vibrato=f=${(4 + 6 * k).toStringAsFixed(1)}:d=${(0.3 + 0.5 * k).toStringAsFixed(2)}';
    case 7:
      return 'bass=g=${(4 + 14 * k).round()}:f=110';
    case 8:
      return 'treble=g=${(3 + 10 * k).round()}:f=3500';
    case 9:
      return pitch(1.2 + 0.4 * k);
    case 10:
      return pitch(0.85 - 0.25 * k);
    case 11:
      return 'afftfilt=real=\'hypot(re,im)*cos(0)\':imag=\'hypot(re,im)*sin(0)\':win_size=512:overlap=0.75';
    case 12:
      return 'highpass=f=300,lowpass=f=3400,acompressor';
    case 13:
      return 'highpass=f=200,lowpass=f=4500,aecho=0.6:0.5:15:0.3,volume=1.2';
    case 14:
      return 'apulsator=hz=${(0.1 + 0.4 * k).toStringAsFixed(2)}';
    case 15:
      return 'areverse';
    case 16:
      return 'afade=t=in:st=0:d=${(1 + 4 * k).toStringAsFixed(1)}';
    case 17:
      final d = 1 + 4 * k;
      return 'afade=t=out:st=${math.max(0, dur - d).toStringAsFixed(2)}:d=${d.toStringAsFixed(1)}';
    default:
      return 'volume=${(1.5 + 2.5 * k).toStringAsFixed(2)},alimiter=limit=0.95';
  }
}

/// Peaks (0..1) from a decoded copy of the audio.
Future<List<double>> loadPeaks(String path, {int n = 500}) async {
  final o = await tmpFile('w.raw');
  await runFfmpeg(['-i', path, '-vn', '-ac', '1', '-ar', '8000', '-f', 's16le'], o);
  final b = (await File(o).readAsBytes());
  final bd = ByteData.sublistView(b);
  final total = b.length ~/ 2;
  if (total == 0) return List.filled(n, 0);
  final per = math.max(1, total ~/ n);
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    var mx = 0;
    final s = i * per, e = math.min(total, s + per);
    for (var k = s; k < e; k += math.max(1, per ~/ 40)) {
      final v = bd.getInt16(k * 2, Endian.little).abs();
      if (v > mx) mx = v;
    }
    out.add(mx / 32768);
  }
  final peak = out.fold<double>(0.001, math.max);
  return [for (final v in out) v / peak];
}

class WaveView extends StatelessWidget {
  final List<double> peaks;
  final double r0, r1, playhead;
  final bool range;
  final Color color;
  final void Function(double a, double b)? onRange;
  final ValueChanged<double>? onSeek;
  const WaveView({super.key, required this.peaks, required this.r0, required this.r1, required this.playhead, required this.range, required this.color, this.onRange, this.onSeek});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth;
        int drag = 0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onSeek?.call((d.localPosition.dx / w).clamp(0.0, 1.0).toDouble()),
          onPanStart: (d) {
            final x = d.localPosition.dx / w;
            drag = (x - r0).abs() < (x - r1).abs() ? 1 : 2;
          },
          onPanUpdate: range
              ? (d) {
                  final x = (d.localPosition.dx / w).clamp(0.0, 1.0).toDouble();
                  if (drag == 1) {
                    onRange?.call(math.min(x, r1 - 0.005), r1);
                  } else {
                    onRange?.call(r0, math.max(x, r0 + 0.005));
                  }
                }
              : (d) => onSeek?.call((d.localPosition.dx / w).clamp(0.0, 1.0).toDouble()),
          child: Container(
            height: 120,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            child: ClipRRect(borderRadius: BorderRadius.circular(16), child: CustomPaint(size: Size(w, 120), painter: _WavePainter(peaks, r0, r1, playhead, range, color))),
          ),
        );
      });
}

class _WavePainter extends CustomPainter {
  final List<double> p;
  final double r0, r1, ph;
  final bool range;
  final Color color;
  _WavePainter(this.p, this.r0, this.r1, this.ph, this.range, this.color);
  @override
  void paint(Canvas c, Size s) {
    if (p.isEmpty) return;
    final bw = s.width / p.length;
    final mid = s.height / 2;
    for (var i = 0; i < p.length; i++) {
      final x = i * bw;
      final inside = !range || (x / s.width >= r0 && x / s.width <= r1);
      final h = math.max(2.0, p[i] * (s.height * 0.42));
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + bw / 2, mid), width: math.max(1.5, bw * 0.6), height: h * 2), const Radius.circular(2)),
          Paint()..color = inside ? color : color.withAlpha(60));
    }
    if (range) {
      for (final v in [r0, r1]) {
        c.drawLine(Offset(v * s.width, 0), Offset(v * s.width, s.height), Paint()..color = Colors.white..strokeWidth = 3);
        c.drawCircle(Offset(v * s.width, s.height / 2), 8, Paint()..color = color);
      }
    }
    c.drawLine(Offset(ph * s.width, 0), Offset(ph * s.width, s.height), Paint()..color = const Color(0xFFFFB300)..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _WavePainter o) => true;
}

class AudioStudio extends StatefulWidget {
  final AM mode;
  final String? initial;
  const AudioStudio({super.key, required this.mode, this.initial});
  @override
  State<AudioStudio> createState() => _AudioStudioState();
}

class _AudioStudioState extends State<AudioStudio> {
  final ins = <String>[];
  final names = <String>[];
  final vols = <double>[];
  final delays = <double>[];
  int cur = 0;
  VideoPlayerController? pc, oc;
  List<double> peaks = [], outPeaks = [];
  bool showOut = false, busy = false;
  String? out, outExt, error;
  double r0 = 0, r1 = 1, speed = 1.25, fxK = 0.5, rate = 1;
  int fmt = 0, fxI = 0, enh = 1;

  AM get m => widget.mode;
  bool get multi => m == AM.merge || m == AM.mix;
  bool get hasRange => m == AM.trim || m == AM.speed || m == AM.fx;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      ins.add(widget.initial!);
      names.add(widget.initial!.split(RegExp(r'[\\/]')).last);
      vols.add(1);
      delays.add(0);
      _load(0);
    }
  }

  @override
  void dispose() {
    pc?.dispose();
    oc?.dispose();
    super.dispose();
  }

  Future<void> _load(int i) async {
    await pc?.dispose();
    final c = VideoPlayerController.file(File(ins[i]));
    pc = c;
    try {
      await c.initialize();
      c.addListener(() {
        if (!mounted) return;
        final d = c.value.duration.inMilliseconds;
        if (hasRange && d > 0 && c.value.isPlaying && c.value.position.inMilliseconds >= d * r1) {
          c.seekTo(Duration(milliseconds: (d * r0).round()));
        }
        setState(() {});
      });
      if (m == AM.speed) await c.setPlaybackSpeed(speed);
      peaks = await loadPeaks(ins[i]);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() {});
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: multi);
    if (r == null) return;
    if (!multi) {
      ins.clear();
      names.clear();
      vols.clear();
      delays.clear();
    }
    for (final f in r.files) {
      if (f.path != null) {
        ins.add(f.path!);
        names.add(f.name);
        vols.add(1);
        delays.add(0);
      }
    }
    cur = multi ? ins.length - 1 : 0;
    out = null;
    showOut = false;
    r0 = 0;
    r1 = 1;
    error = null;
    await _load(cur);
  }

  double get durS => (pc?.value.duration.inMilliseconds ?? 0) / 1000;

  Future<List<String>> args({bool preview = false}) async {
    final a = r0 * durS, b = r1 * durS;
    final i0 = ins[cur];
    switch (m) {
      case AM.merge:
        return [for (final i in ins) ...['-i', i], '-filter_complex', '${List.generate(ins.length, (i) => '[$i:a]').join()}concat=n=${ins.length}:v=0:a=1[a]', '-map', '[a]', ...formats[fmt].$3];
      case AM.mix:
        final f = StringBuffer();
        for (var i = 0; i < ins.length; i++) {
          final dl = (delays[i] * 1000).round();
          f.write('[$i:a]volume=${vols[i].toStringAsFixed(2)}${dl > 0 ? ',adelay=$dl|$dl' : ''}[a$i];');
        }
        f.write('${List.generate(ins.length, (i) => '[a$i]').join()}amix=inputs=${ins.length}:duration=longest:normalize=0[a]');
        return [for (final i in ins) ...['-i', i], '-filter_complex', f.toString(), '-map', '[a]', ...formats[fmt].$3];
      case AM.trim:
        return ['-ss', secs(a), '-to', secs(b), '-i', i0, ...formats[fmt].$3];
      case AM.speed:
        final sel = r0 > 0 || r1 < 1 ? ['-ss', secs(a), '-to', secs(b)] : <String>[];
        return [...sel, '-i', i0, '-af', atempo(speed).join(','), ...formats[fmt].$3];
      case AM.convert:
        return ['-i', i0, '-vn', ...formats[fmt].$3];
      case AM.enhance:
        final model = await tmpFile('bd.rnnn');
        await File(model).writeAsBytes((await rootBundle.load('assets/models/bd.rnnn')).buffer.asUint8List());
        final mp = model.replaceAll('\\', '/').replaceAll(':', '\\:');
        final chain = switch (enh) {
          0 => 'highpass=f=70,afftdn=nr=12:nf=-35,loudnorm=I=-16:TP=-1.5',
          1 => 'highpass=f=80,arnndn=m=\'$mp\',afftdn=nr=10:nf=-40,equalizer=f=3000:t=q:w=1:g=2,acompressor=threshold=-18dB:ratio=3,loudnorm=I=-16:TP=-1.5',
          _ => 'highpass=f=90,lowpass=f=12000,arnndn=m=\'$mp\',arnndn=m=\'$mp\',afftdn=nr=20:nf=-45,acompressor=threshold=-20dB:ratio=4,loudnorm=I=-16:TP=-1.5',
        };
        return ['-i', i0, '-vn', '-af', chain, '-ar', '44100', ...formats[0].$3];
      case AM.fx:
        final sel = r0 > 0 || r1 < 1 ? ['-ss', secs(a), '-to', secs(b)] : <String>[];
        return [...sel, '-i', i0, '-af', fxFilter(fxI, fxK, b - a), ...formats[0].$3];
    }
  }

  Future<void> run() async {
    if (ins.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var a = await args();
      final ext = (m == AM.enhance || m == AM.fx) ? 'mp3' : formats[fmt].$2;
      final o = await tmpFile('out.$ext');
      try {
        await runFfmpeg(a, o);
      } catch (e) {
        // fall back without optional filters (arnndn / normalize may be missing)
        if (m == AM.enhance) {
          a = ['-i', ins[cur], '-vn', '-af', 'highpass=f=80,afftdn=nr=18:nf=-35,acompressor=threshold=-18dB:ratio=3,loudnorm=I=-16:TP=-1.5', ...formats[0].$3];
          await runFfmpeg(a, o);
        } else if (m == AM.mix) {
          final s = a.map((e) => e.replaceAll(':normalize=0', '')).toList();
          await runFfmpeg(s, o);
        } else {
          rethrow;
        }
      }
      await oc?.dispose();
      final c = VideoPlayerController.file(File(o));
      await c.initialize();
      outPeaks = await loadPeaks(o);
      if (mounted) {
        setState(() {
          oc = c;
          out = o;
          outExt = ext;
          showOut = true;
        });
        c.play();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (out == null) return;
    final p = await saveFileCopy(out!, '${baseName(names.isEmpty ? 'audio' : names[cur])}_edited.$outExt');
    if (p != null && mounted) toast(context, t(context, 'تم الحفظ', 'Saved'));
  }

  Widget stage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = showOut && oc != null ? oc : pc;
    final pk = showOut && oc != null ? outPeaks : peaks;
    final ready = c != null && c.value.isInitialized;
    final d = ready ? c.value.duration.inMilliseconds : 0;
    final ph = ready && d > 0 ? c.value.position.inMilliseconds / d : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!ready)
        InkWell(
          onTap: pick,
          child: Container(
            height: 120,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.graphic_eq, size: 40, color: cs.primary), Text(t(context, 'اضغط لاختيار ملف صوتي', 'Tap to choose audio'))])),
          ),
        )
      else
        WaveView(
          peaks: pk,
          r0: r0,
          r1: r1,
          playhead: ph,
          range: hasRange && !showOut,
          color: cs.primary,
          onRange: (a, b) => setState(() {
            r0 = a;
            r1 = b;
          }),
          onSeek: (v) => c.seekTo(Duration(milliseconds: (d * v).round())),
        ),
      if (ready)
        Row(children: [
          IconButton(icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 36), onPressed: () => c.value.isPlaying ? c.pause() : c.play()),
          Text('${clock(c.value.position)} / ${clock(c.value.duration)}', style: const TextStyle(fontSize: 12)),
          const Spacer(),
          if (hasRange && !showOut)
            Text('${clock(Duration(milliseconds: (d * r0).round()))} → ${clock(Duration(milliseconds: (d * r1).round()))}', style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w700)),
        ]),
      if (out != null && oc != null)
        Segs(items: [('الأصلي', 'Original'), ('النتيجة', 'Result')], sel: showOut ? 1 : 0, onChanged: (i) async {
          await pc?.pause();
          await oc?.pause();
          setState(() => showOut = i == 1);
        }),
    ]);
  }

  List<Widget> options(BuildContext context) {
    Widget fmtPanel() => Panel(title: t(context, 'الصيغة', 'Format'), child: Segs(items: [for (final f in formats) (f.$1, f.$1)], sel: fmt, onChanged: (i) => setState(() => fmt = i)));
    switch (m) {
      case AM.merge:
        return [_list(context), fmtPanel()];
      case AM.mix:
        return [_list(context), fmtPanel()];
      case AM.trim:
        return [Panel(child: Text(t(context, 'حرّك المقبضين على الموجة الصوتية لتحديد الجزء.', 'Drag the handles on the waveform to set the part.'))), fmtPanel()];
      case AM.speed:
        return [
          Panel(title: t(context, 'السرعة', 'Speed'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Sld(t(context, 'السرعة', 'Speed'), speed, 0.25, 4, (v) { setState(() => speed = v); pc?.setPlaybackSpeed(v); }, divisions: 15, fmt: (v) => '×${v.toStringAsFixed(2)}'),
            Text(t(context, 'تُطبَّق على الجزء المحدد فقط إن حددت جزءًا.', 'Applies only to the selected part if you selected one.'), style: const TextStyle(fontSize: 12)),
          ])),
          fmtPanel(),
        ];
      case AM.convert:
        return [fmtPanel()];
      case AM.enhance:
        return [Panel(title: t(context, 'تحسين الصوت', 'Enhance'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Segs(items: [('خفيف', 'Light'), ('صوت بشري (موصى به)', 'Voice (recommended)'), ('إزالة ضجيج قوية', 'Strong denoise')], sel: enh, onChanged: (i) => setState(() => enh = i)),
          const SizedBox(height: 6),
          Text(t(context, 'يزيل الضجيج المحيط ويوضّح الكلام ويوازن مستوى الصوت. قارن بين الأصلي والنتيجة قبل الحفظ.', 'Removes background noise, clarifies speech and levels volume. Compare before saving.'), style: const TextStyle(fontSize: 12)),
        ]))];
      case AM.fx:
        return [Panel(title: t(context, 'المؤثرات', 'Effects'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Segs(items: fxList, sel: fxI, onChanged: (i) => setState(() => fxI = i)),
          Sld(t(context, 'الشدة', 'Intensity'), fxK, 0, 1, (v) => setState(() => fxK = v)),
        ]))];
    }
  }

  Widget _list(BuildContext context) => Panel(
        title: t(context, 'الملفات', 'Files'),
        child: Column(children: [
          if (ins.isEmpty) Text(t(context, 'أضف ملفين أو أكثر', 'Add two or more files')),
          for (var i = 0; i < ins.length; i++)
            Column(children: [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: cur == i,
                title: Text(names[i], overflow: TextOverflow.ellipsis),
                onTap: () async { cur = i; await _load(i); },
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.arrow_upward, size: 18), onPressed: i == 0 ? null : () => setState(() { for (final l in [ins, names, vols, delays]) { l.insert(i - 1, l.removeAt(i) as dynamic); } })),
                  IconButton(icon: const Icon(Icons.arrow_downward, size: 18), onPressed: i == ins.length - 1 ? null : () => setState(() { for (final l in [ins, names, vols, delays]) { l.insert(i + 1, l.removeAt(i) as dynamic); } })),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () async { ins.removeAt(i); names.removeAt(i); vols.removeAt(i); delays.removeAt(i); cur = 0; if (ins.isNotEmpty) { await _load(0); } else { await pc?.dispose(); pc = null; peaks = []; } setState(() {}); }),
                ]),
              ),
              if (m == AM.mix) ...[
                Sld(t(context, 'مستوى الصوت', 'Volume'), vols[i], 0, 3, (v) => setState(() => vols[i] = v), fmt: (v) => '${(v * 100).round()}%'),
                Sld(t(context, 'تأخير البداية (ثانية)', 'Start delay (s)'), delays[i], 0, 30, (v) => setState(() => delays[i] = v), fmt: (v) => v.toStringAsFixed(1)),
              ],
            ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(child: FilledButton.tonalIcon(onPressed: pick, icon: const Icon(Icons.folder_open), label: Text(multi ? t(context, 'إضافة ملفات', 'Add files') : t(context, 'اختيار ملف صوتي', 'Choose audio file')))),
      ...options(context),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BusyButton(t(context, 'تنفيذ', 'Run'), busy: busy, onTap: ins.length < (multi ? 2 : 1) ? null : run),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: out == null ? null : save, icon: const Icon(Icons.save_alt), label: Text(t(context, 'حفظ', 'Save'))),
        if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
      ])),
    ]);
    return StudioLayout(stage: stage(context), side: side);
  }
}
