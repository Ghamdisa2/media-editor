import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'strings.dart';

typedef V = Map<String, Object>;

extension VX on Map<String, Object> {
  double d(String k) => (this[k] as num).toDouble();
  int i(String k) => (this[k] as num).round();
  String s(String k) => this[k] as String;
}

// ---------- FFmpeg engine ----------
/// Windows: bundled ffmpeg.exe next to the app. Android: ffmpeg-kit.
Future<void> runFfmpeg(List<String> args, String out) async {
  final all = ['-y', '-hide_banner', '-nostdin', ...args, out];
  if (Platform.isWindows) {
    final local =
        '${File(Platform.resolvedExecutable).parent.path}\\ffmpeg.exe';
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

String _ext(String path) =>
    path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : 'mp4';

const _enc = [
  '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
  '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k'
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
  const FOpt.slider(this.key, this.ar, this.en, this.min, this.max, this.def,
      {this.div})
      : kind = FK.slider,
        choices = const [],
        text = '';
  const FOpt.choice(this.key, this.ar, this.en, this.choices)
      : kind = FK.choice,
        min = 0,
        max = 0,
        def = 0,
        div = null,
        text = '';
  const FOpt.text(this.key, this.ar, this.en, this.text)
      : kind = FK.text,
        min = 0,
        max = 0,
        def = 0,
        div = null,
        choices = const [];
}

typedef Build = Future<List<String>> Function(
    List<String> ins, String? img, V v, Directory tmp);

class FfmpegTool extends StatefulWidget {
  final FileType type;
  final bool multi, needsImage;
  final List<FOpt> opts;
  final Build build;
  final String Function(List<String> ins, V v) ext;
  const FfmpegTool(
      {super.key,
      required this.type,
      required this.opts,
      required this.build,
      required this.ext,
      this.multi = false,
      this.needsImage = false});
  @override
  State<FfmpegTool> createState() => _FfmpegToolState();
}

class _FfmpegToolState extends State<FfmpegTool> {
  final ins = <String>[];
  final names = <String>[];
  String? img;
  String? out, outExt, error;
  bool busy = false;
  late final V v = {
    for (final o in widget.opts)
      o.key: o.kind == FK.text ? o.text : (o.kind == FK.slider ? o.def : 0)
  };
  late final ctrls = {
    for (final o in widget.opts)
      if (o.kind == FK.text) o.key: TextEditingController(text: o.text)
  };

  Future<void> pick() async {
    final r = await FilePicker.platform
        .pickFiles(type: widget.type, allowMultiple: widget.multi);
    if (r == null) return;
    setState(() {
      if (!widget.multi) {
        ins.clear();
        names.clear();
      }
      for (final f in r.files) {
        if (f.path != null) {
          ins.add(f.path!);
          names.add(f.name);
        }
      }
      out = null;
      error = null;
    });
  }

  Future<void> pickImg() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final p = r?.files.single.path;
    if (p != null) setState(() => img = p);
  }

  Future<void> apply() async {
    setState(() {
      busy = true;
      error = null;
      out = null;
    });
    try {
      for (final e in ctrls.entries) {
        v[e.key] = e.value.text;
      }
      final dir = await Directory.systemTemp.createTemp('me_');
      final e = widget.ext(ins, v);
      final o = '${dir.path}${Platform.pathSeparator}out.$e';
      final args = await widget.build(ins, img, v, dir);
      await runFfmpeg(args, o);
      if (mounted) {
        setState(() {
          out = o;
          outExt = e;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final o = out;
    if (o == null) return;
    final n = names.first;
    final base = n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;
    final fn = '${base}_edited.$outExt';
    String? p;
    if (Platform.isAndroid || Platform.isIOS) {
      p = await FilePicker.platform
          .saveFile(fileName: fn, bytes: await File(o).readAsBytes());
    } else {
      p = await FilePicker.platform.saveFile(fileName: fn);
      if (p != null) await File(o).copy(p);
    }
    if (p != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(context, 'تم الحفظ', 'Saved'))));
    }
  }

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
                onSelected: (_) => setState(() => v[o.key] = i),
              )
          ]),
        ]);
      case FK.slider:
        final x = (v[o.key] as num).toDouble();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label: ${x.toStringAsFixed(o.max <= 5 ? 2 : 0)}'),
          Slider(
              value: x,
              min: o.min,
              max: o.max,
              divisions: o.div,
              onChanged: (n) => setState(() => v[o.key] = n)),
        ]);
      case FK.text:
        return TextField(
            controller: ctrls[o.key],
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final need = widget.multi ? 2 : 1;
    final ready = ins.length >= need && (!widget.needsImage || img != null);
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
            onPressed: pick,
            icon: const Icon(Icons.folder_open),
            label: Text(widget.multi
                ? t(context, 'إضافة ملفات', 'Add files')
                : t(context, 'اختيار ملف', 'Choose file'))),
        if (widget.needsImage) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
              onPressed: pickImg,
              icon: const Icon(Icons.image_outlined),
              label: Text(t(context, 'اختيار صورة العلامة', 'Choose watermark image'))),
        ],
        const SizedBox(height: 16),
        for (final o in widget.opts) ...[control(o), const SizedBox(height: 12)],
        FilledButton(
            onPressed: ready && !busy ? apply : null,
            child: Text(t(context, 'تنفيذ', 'Run'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: out == null ? null : save,
            icon: const Icon(Icons.save_alt),
            label: Text(t(context, 'حفظ', 'Save'))),
      ],
    );
    final info = Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        if (ins.isEmpty)
          Text(t(context, 'اختر ملفًا للبدء', 'Choose a file to start')),
        for (var i = 0; i < names.length; i++)
          ListTile(
            dense: true,
            leading: Text('${i + 1}'),
            title: Text(names[i], overflow: TextOverflow.ellipsis),
            trailing: widget.multi
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                          ins.removeAt(i);
                          names.removeAt(i);
                        }))
                : null,
          ),
        if (widget.needsImage && img != null)
          ListTile(
              dense: true,
              leading: const Icon(Icons.image_outlined),
              title: Text(img!.split(RegExp(r'[\\/]')).last)),
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(t(context, 'جاري المعالجة...', 'Processing...')),
        ],
        if (out != null) ...[
          const SizedBox(height: 16),
          Text(
              '${t(context, 'تم', 'Done')} - ${(File(out!).lengthSync() / 1048576).toStringAsFixed(2)} MB',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          SelectableText(error!, style: TextStyle(color: cs.error)),
        ],
      ]),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 800) {
          return Row(children: [
            SizedBox(width: 340, child: SingleChildScrollView(child: panel)),
            const SizedBox(width: 16),
            Expanded(child: info),
          ]);
        }
        return Column(children: [
          Expanded(child: info),
          const SizedBox(height: 12),
          SizedBox(height: 320, child: SingleChildScrollView(child: panel)),
        ]);
      }),
    );
  }
}

// ---------- tool definitions ----------
const _vt = FileType.video;
const _at = FileType.audio;

String _sameExt(List<String> i, V v) => _ext(i.first);
String _mp4(List<String> i, V v) => 'mp4';

List<(String, String)> _c(List<String> xs) => [for (final x in xs) (x, x)];

String _font(String text) {
  final ar = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  final list = Platform.isWindows
      ? ['C:/Windows/Fonts/arial.ttf']
      : [
          if (ar) '/system/fonts/NotoNaskhArabic-Regular.ttf',
          if (ar) '/system/fonts/NotoSansArabic-Regular.ttf',
          '/system/fonts/Roboto-Regular.ttf',
          '/system/fonts/DroidSans.ttf'
        ];
  final f = list.firstWhere((e) => File(e).existsSync(), orElse: () => list.last);
  return f.replaceAll(':', '\\:');
}

Widget? ffmpegTool(String id) {
  switch (id) {
    case 'v_crop':
      return FfmpegTool(
        type: _vt,
        opts: [
          FOpt.choice('r', 'النسبة', 'Ratio',
              const [('1:1', '1:1'), ('16:9', '16:9'), ('9:16', '9:16'), ('4:3', '4:3'), ('3:4', '3:4')]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final r = [1.0, 16 / 9, 9 / 16, 4 / 3, 3 / 4][v.i('r')];
          return [
            '-i', ins[0], '-vf',
            "crop=w='if(gt(iw/ih,$r),ih*$r,iw)':h='if(gt(iw/ih,$r),ih,iw/$r)',scale=trunc(iw/2)*2:trunc(ih/2)*2",
            ..._enc
          ];
        },
      );
    case 'v_blur':
      return FfmpegTool(
        type: _vt,
        opts: const [FOpt.slider('r', 'قوة التمويه', 'Blur', 2, 30, 10, div: 28)],
        ext: _mp4,
        build: (ins, img, v, tmp) async =>
            ['-i', ins[0], '-vf', 'boxblur=${v.i('r')}:2', ..._enc],
      );
    case 'v_trim':
      return FfmpegTool(
        type: _vt,
        opts: const [
          FOpt.text('s', 'البداية (HH:MM:SS)', 'Start (HH:MM:SS)', '00:00:00'),
          FOpt.text('e', 'النهاية (HH:MM:SS)', 'End (HH:MM:SS)', '00:00:10'),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async =>
            ['-ss', v.s('s'), '-to', v.s('e'), '-i', ins[0], ..._enc],
      );
    case 'v_enhance':
      return FfmpegTool(
        type: _vt,
        opts: [
          const FOpt.slider('c', 'التباين', 'Contrast', 0.8, 1.4, 1.1, div: 12),
          const FOpt.slider('s', 'التشبع', 'Saturation', 0.5, 1.8, 1.2, div: 13),
          const FOpt.slider('u', 'الحدة', 'Sharpness', 0, 2, 0.8, div: 8),
          FOpt.choice('n', 'إزالة التشويش', 'Denoise',
              const [('لا', 'Off'), ('نعم', 'On')]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async => [
          '-i', ins[0], '-vf',
          '${v.i('n') == 1 ? 'hqdn3d=2:1:3:3,' : ''}eq=contrast=${v.d('c')}:saturation=${v.d('s')},unsharp=5:5:${v.d('u')}',
          ..._enc
        ],
      );
    case 'v_merge':
      return FfmpegTool(
        type: _vt,
        multi: true,
        opts: const [],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final n = ins.length;
          final f = StringBuffer();
          for (var i = 0; i < n; i++) {
            f.write(
                '[$i:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v$i];');
            f.write('[$i:a]aformat=sample_rates=44100:channel_layouts=stereo[a$i];');
          }
          for (var i = 0; i < n; i++) {
            f.write('[v$i][a$i]');
          }
          f.write('concat=n=$n:v=1:a=1[v][a]');
          return [
            for (final i in ins) ...['-i', i],
            '-filter_complex', f.toString(), '-map', '[v]', '-map', '[a]', ..._enc
          ];
        },
      );
    case 'v_mp3':
      return FfmpegTool(
        type: _vt,
        opts: const [],
        ext: (i, v) => 'mp3',
        build: (ins, img, v, tmp) async =>
            ['-i', ins[0], '-vn', '-c:a', 'libmp3lame', '-q:a', '2'],
      );
    case 'v_flip':
      return FfmpegTool(
        type: _vt,
        opts: const [
          FOpt.choice('m', 'الإجراء', 'Action', [
            ('قلب أفقي', 'Flip horizontal'),
            ('قلب عمودي', 'Flip vertical'),
            ('تدوير 90°', 'Rotate 90°'),
            ('تدوير 180°', 'Rotate 180°')
          ]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async => [
          '-i', ins[0], '-vf',
          ['hflip', 'vflip', 'transpose=1', 'hflip,vflip'][v.i('m')],
          ..._enc
        ],
      );
    case 'v_speed':
      return FfmpegTool(
        type: _vt,
        opts: const [FOpt.slider('s', 'السرعة', 'Speed', 0.25, 4, 2, div: 15)],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final s = v.d('s');
          return [
            '-i', ins[0], '-vf', 'setpts=PTS/$s', '-af', _atempo(s).join(','),
            ..._enc
          ];
        },
      );
    case 'v_frame':
      return FfmpegTool(
        type: _vt,
        opts: const [
          FOpt.choice('a', 'الإطار', 'Frame', [
            ('16:9', '16:9'), ('9:16', '9:16'), ('1:1', '1:1'), ('4:5', '4:5')
          ]),
          FOpt.choice('m', 'الخلفية', 'Background',
              [('أسود', 'Black'), ('تمويه', 'Blurred')]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final sz = [(1920, 1080), (1080, 1920), (1080, 1080), (1080, 1350)][v.i('a')];
          final w = sz.$1, h = sz.$2;
          if (v.i('m') == 0) {
            return [
              '-i', ins[0], '-vf',
              'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1',
              ..._enc
            ];
          }
          return [
            '-i', ins[0], '-filter_complex',
            '[0:v]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,boxblur=20:5[bg];[0:v]scale=$w:$h:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2,setsar=1',
            ..._enc
          ];
        },
      );
    case 'v_convert':
      const fm = ['mp4', 'mkv', 'webm', 'avi', 'mov', 'gif'];
      return FfmpegTool(
        type: _vt,
        opts: [FOpt.choice('f', 'الصيغة', 'Format', _c(['MP4', 'MKV', 'WEBM', 'AVI', 'MOV', 'GIF']))],
        ext: (i, v) => fm[v.i('f')],
        build: (ins, img, v, tmp) async {
          switch (fm[v.i('f')]) {
            case 'webm':
              return ['-i', ins[0], '-c:v', 'libvpx-vp9', '-crf', '32', '-b:v', '0', '-c:a', 'libopus'];
            case 'avi':
              return ['-i', ins[0], '-c:v', 'mpeg4', '-q:v', '4', '-c:a', 'libmp3lame'];
            case 'gif':
              return ['-i', ins[0], '-vf', 'fps=12,scale=480:-1:flags=lanczos', '-an'];
            default:
              return ['-i', ins[0], ..._enc];
          }
        },
      );
    case 'v_compress':
      return FfmpegTool(
        type: _vt,
        opts: [
          const FOpt.slider('q', 'مستوى الضغط (أعلى = أصغر)', 'Compression (higher = smaller)', 18, 38, 28, div: 20),
          FOpt.choice('h', 'الارتفاع', 'Height',
              const [('الأصلي', 'Original'), ('1080', '1080'), ('720', '720'), ('480', '480')]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final h = [0, 1080, 720, 480][v.i('h')];
          return [
            '-i', ins[0],
            if (h > 0) ...['-vf', 'scale=-2:$h'],
            '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '${v.i('q')}',
            '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k'
          ];
        },
      );
    case 'v_text':
      return FfmpegTool(
        type: _vt,
        opts: [
          const FOpt.text('t', 'النص', 'Text', 'Media Editor'),
          const FOpt.slider('z', 'حجم الخط', 'Font size', 16, 160, 48, div: 36),
          FOpt.choice('c', 'اللون', 'Color',
              const [('أبيض', 'White'), ('أسود', 'Black'), ('أصفر', 'Yellow'), ('أحمر', 'Red')]),
          FOpt.choice('p', 'الموضع', 'Position',
              const [('أعلى', 'Top'), ('وسط', 'Center'), ('أسفل', 'Bottom')]),
          FOpt.choice('b', 'خلفية للنص', 'Text box',
              const [('بدون', 'None'), ('شبه شفافة', 'Translucent')]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final txt = File('${tmp.path}${Platform.pathSeparator}t.txt');
          await txt.writeAsString(v.s('t'));
          final tp = txt.path.replaceAll('\\', '/').replaceAll(':', '\\:');
          final col = ['white', 'black', 'yellow', 'red'][v.i('c')];
          final y = ['h*0.06', '(h-text_h)/2', 'h-text_h-h*0.06'][v.i('p')];
          final box = v.i('b') == 1 ? ':box=1:boxcolor=black@0.5:boxborderw=12' : '';
          return [
            '-i', ins[0], '-vf',
            "drawtext=fontfile='${_font(v.s('t'))}':textfile='$tp':fontsize=${v.i('z')}:fontcolor=$col:x=(w-text_w)/2:y=$y$box",
            ..._enc
          ];
        },
      );
    case 'v_wm_add':
      return FfmpegTool(
        type: _vt,
        needsImage: true,
        opts: [
          const FOpt.slider('s', 'حجم العلامة %', 'Size %', 5, 40, 15, div: 35),
          const FOpt.slider('o', 'الشفافية', 'Opacity', 0.1, 1, 0.8, div: 9),
          FOpt.choice('p', 'الموضع', 'Position', const [
            ('أعلى يسار', 'Top left'), ('أعلى يمين', 'Top right'),
            ('أسفل يسار', 'Bottom left'), ('أسفل يمين', 'Bottom right'), ('وسط', 'Center')
          ]),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final pos = [
            'x=20:y=20', 'x=main_w-overlay_w-20:y=20',
            'x=20:y=main_h-overlay_h-20', 'x=main_w-overlay_w-20:y=main_h-overlay_h-20',
            'x=(main_w-overlay_w)/2:y=(main_h-overlay_h)/2'
          ][v.i('p')];
          return [
            '-i', ins[0], '-i', img!, '-filter_complex',
            '[1:v][0:v]scale2ref=w=main_w*${v.d('s') / 100}:h=ow/a[wm][bg];[wm]format=rgba,colorchannelmixer=aa=${v.d('o')}[w2];[bg][w2]overlay=$pos',
            ..._enc
          ];
        },
      );
    case 'v_wm_remove':
      return FfmpegTool(
        type: _vt,
        opts: const [
          FOpt.slider('x', 'موضع المنطقة أفقيًا %', 'Area X %', 0, 95, 70, div: 95),
          FOpt.slider('y', 'موضع المنطقة عموديًا %', 'Area Y %', 0, 95, 5, div: 95),
          FOpt.slider('w', 'عرض المنطقة %', 'Area width %', 2, 60, 25, div: 58),
          FOpt.slider('h', 'ارتفاع المنطقة %', 'Area height %', 2, 60, 10, div: 58),
        ],
        ext: _mp4,
        build: (ins, img, v, tmp) async {
          final x = v.i('x'), y = v.i('y'), w = v.i('w'), h = v.i('h');
          return [
            '-i', ins[0], '-filter_complex',
            '[0:v]split[a][b];[b]crop=iw*$w/100:ih*$h/100:iw*$x/100:ih*$y/100,boxblur=14:4[c];[a][c]overlay=main_w*$x/100:main_h*$y/100',
            ..._enc
          ];
        },
      );
    // ---- audio ----
    case 'a_merge':
      return FfmpegTool(
        type: _at,
        multi: true,
        opts: const [],
        ext: (i, v) => 'mp3',
        build: (ins, img, v, tmp) async => [
          for (final i in ins) ...['-i', i],
          '-filter_complex',
          '${List.generate(ins.length, (i) => '[$i:a]').join()}concat=n=${ins.length}:v=0:a=1[a]',
          '-map', '[a]', '-c:a', 'libmp3lame', '-q:a', '2'
        ],
      );
    case 'a_mix':
      return FfmpegTool(
        type: _at,
        multi: true,
        opts: const [],
        ext: (i, v) => 'mp3',
        build: (ins, img, v, tmp) async => [
          for (final i in ins) ...['-i', i],
          '-filter_complex',
          '${List.generate(ins.length, (i) => '[$i:a]').join()}amix=inputs=${ins.length}:duration=longest[a]',
          '-map', '[a]', '-c:a', 'libmp3lame', '-q:a', '2'
        ],
      );
    case 'a_trim':
      return FfmpegTool(
        type: _at,
        opts: const [
          FOpt.text('s', 'البداية (HH:MM:SS)', 'Start (HH:MM:SS)', '00:00:00'),
          FOpt.text('e', 'النهاية (HH:MM:SS)', 'End (HH:MM:SS)', '00:00:10'),
        ],
        ext: _sameExt,
        build: (ins, img, v, tmp) async =>
            ['-ss', v.s('s'), '-to', v.s('e'), '-i', ins[0]],
      );
    case 'a_speed':
      return FfmpegTool(
        type: _at,
        opts: const [FOpt.slider('s', 'السرعة', 'Speed', 0.25, 4, 1.5, div: 15)],
        ext: _sameExt,
        build: (ins, img, v, tmp) async =>
            ['-i', ins[0], '-af', _atempo(v.d('s')).join(',')],
      );
    case 'a_convert':
      const af = ['mp3', 'wav', 'm4a', 'ogg', 'flac'];
      return FfmpegTool(
        type: _at,
        opts: [FOpt.choice('f', 'الصيغة', 'Format', _c(['MP3', 'WAV', 'M4A', 'OGG', 'FLAC']))],
        ext: (i, v) => af[v.i('f')],
        build: (ins, img, v, tmp) async => [
          '-i', ins[0], '-vn',
          if (v.i('f') == 0) ...['-c:a', 'libmp3lame', '-q:a', '2']
        ],
      );
    case 'a_enhance':
      return FfmpegTool(
        type: _at,
        opts: [
          FOpt.choice('n', 'قوة إزالة الضجيج', 'Noise reduction',
              const [('خفيفة', 'Light'), ('متوسطة', 'Medium'), ('قوية', 'Strong')]),
        ],
        ext: (i, v) => 'mp3',
        build: (ins, img, v, tmp) async => [
          '-i', ins[0], '-af',
          'highpass=f=80,afftdn=nr=${[10, 20, 30][v.i('n')]}:nf=-30,loudnorm',
          '-c:a', 'libmp3lame', '-q:a', '2'
        ],
      );
  }
  return null;
}
