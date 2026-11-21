import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'common.dart';
import 'composer.dart';
import 'strings.dart';

// ---------- FFmpeg engine (shared with audio) ----------
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

const enc = [
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
  '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k'
];

List<String> atempo(double s) {
  if (s > 2) return ['atempo=2', 'atempo=${s / 2}'];
  if (s < 0.5) return ['atempo=0.5', 'atempo=${s / 0.5}'];
  return ['atempo=$s'];
}

String extOf(String p) => p.contains('.') ? p.substring(p.lastIndexOf('.') + 1) : 'mp4';
String baseName(String n) => n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;

// ---------- region selector over the video ----------
class RegionBox extends StatefulWidget {
  final Rect rect; // normalised
  final double? pixelRatio; // lock w/h in pixels; needs videoAspect
  final double videoAspect;
  final bool ellipse, dim;
  final ValueChanged<Rect> onChanged;
  const RegionBox(
      {super.key,
      required this.rect,
      required this.onChanged,
      required this.videoAspect,
      this.pixelRatio,
      this.ellipse = false,
      this.dim = true});
  @override
  State<RegionBox> createState() => _RegionBoxState();
}

class _RegionBoxState extends State<RegionBox> {
  int mode = 0; // 0 move, 1..4 corners (tl,tr,bl,br)

  Rect _fix(Rect r) {
    double w = r.width.clamp(0.05, 1.0).toDouble(), h = r.height.clamp(0.05, 1.0).toDouble();
    if (widget.pixelRatio != null) {
      h = w * widget.videoAspect / widget.pixelRatio!;
      if (h > 1) {
        h = 1;
        w = h * widget.pixelRatio! / widget.videoAspect;
      }
    }
    final x = r.left.clamp(0.0, 1 - w).toDouble(), y = r.top.clamp(0.0, 1 - h).toDouble();
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final sz = Size(c.maxWidth, c.maxHeight);
        final r = widget.rect;
        final px = Rect.fromLTWH(r.left * sz.width, r.top * sz.height, r.width * sz.width, r.height * sz.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final p = d.localPosition;
            final cs = [px.topLeft, px.topRight, px.bottomLeft, px.bottomRight];
            mode = 0;
            for (var i = 0; i < 4; i++) {
              if ((cs[i] - p).distance < 28) mode = i + 1;
            }
          },
          onPanUpdate: (d) {
            final dx = d.delta.dx / sz.width, dy = d.delta.dy / sz.height;
            var n = r;
            switch (mode) {
              case 0:
                n = r.shift(Offset(dx, dy));
              case 1:
                n = Rect.fromLTRB(r.left + dx, r.top + dy, r.right, r.bottom);
              case 2:
                n = Rect.fromLTRB(r.left, r.top + dy, r.right + dx, r.bottom);
              case 3:
                n = Rect.fromLTRB(r.left + dx, r.top, r.right, r.bottom + dy);
              default:
                n = Rect.fromLTRB(r.left, r.top, r.right + dx, r.bottom + dy);
            }
            if (n.width < 0.05 || n.height < 0.05) return;
            if (mode != 0 && widget.pixelRatio != null) {
              final w = n.width;
              final h = w * widget.videoAspect / widget.pixelRatio!;
              n = (mode == 1 || mode == 3)
                  ? Rect.fromLTWH(r.right - w, mode == 1 ? r.bottom - h : r.top, w, h)
                  : Rect.fromLTWH(r.left, mode == 2 ? r.bottom - h : r.top, w, h);
            }
            widget.onChanged(_fix(n));
          },
          child: CustomPaint(
              size: sz,
              painter: _RegionPainter(px, widget.ellipse, widget.dim, Theme.of(context).colorScheme.primary)),
        );
      });
}

class _RegionPainter extends CustomPainter {
  final Rect r;
  final bool ellipse, dim;
  final Color accent;
  _RegionPainter(this.r, this.ellipse, this.dim, this.accent);
  @override
  void paint(Canvas c, Size s) {
    final shape = Path()..addRect(r);
    if (ellipse) {
      shape
        ..reset()
        ..addOval(r);
    }
    if (dim) {
      final all = Path()..addRect(Offset.zero & s);
      c.drawPath(Path.combine(PathOperation.difference, all, shape), Paint()..color = const Color(0x88000000));
    }
    c.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      c.drawCircle(p, 8, Paint()..color = accent);
      c.drawCircle(
          p,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RegionPainter o) => true;
}

// ---------- video tool screen ----------
enum VM { crop, blur, trim, enhance, merge, mp3, flip, speed, frame, convert, compress, text, wm, wmRemove }

VM? vmFor(String id) => switch (id) {
      'v_crop' => VM.crop,
      'v_blur' => VM.blur,
      'v_trim' => VM.trim,
      'v_enhance' => VM.enhance,
      'v_merge' => VM.merge,
      'v_mp3' => VM.mp3,
      'v_flip' => VM.flip,
      'v_speed' => VM.speed,
      'v_frame' => VM.frame,
      'v_convert' => VM.convert,
      'v_compress' => VM.compress,
      'v_text' => VM.text,
      'v_wm_add' => VM.wm,
      'v_wm_remove' => VM.wmRemove,
      _ => null,
    };

class VideoStudio extends StatefulWidget {
  final VM mode;
  const VideoStudio({super.key, required this.mode});
  @override
  State<VideoStudio> createState() => _VideoStudioState();
}

class _VideoStudioState extends State<VideoStudio> {
  final ins = <String>[];
  final names = <String>[];
  int cur = 0;
  VideoPlayerController? vc, oc; // source / result
  bool showOut = false, busy = false, playing = false;
  String? out, outExt, error, estimate;
  // trim range 0..1
  double r0 = 0, r1 = 1;
  Duration pos = Duration.zero;
  // options
  Rect rect = const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4);
  int ratioIdx = 0, flipIdx = 0, frameA = 0, frameBg = 0, convIdx = 0, hIdx = 0, wmPos = 3, mp3Rate = 1, trimFast = 0, delogoIdx = 0;
  bool ellipse = false, limitTime = false;
  double blurR = 12, speed = 2, crf = 26, eqC = 1.1, eqS = 1.15, eqB = 0.02, sharp = 1.0, denoise = 1, up = 0;
  final cc = ComposerController();
  String? wmImg;

  bool get single => widget.mode != VM.merge;
  VM get m => widget.mode;

  @override
  void dispose() {
    vc?.dispose();
    oc?.dispose();
    cc.dispose();
    super.dispose();
  }

  Duration get dur => vc?.value.duration ?? Duration.zero;
  Size get vsize => vc?.value.size ?? const Size(1920, 1080);
  double get vaspect => (vc?.value.isInitialized ?? false) && vsize.height > 0 ? vsize.width / vsize.height : 16 / 9;

  Future<void> _load(int i) async {
    await vc?.dispose();
    final c = VideoPlayerController.file(File(ins[i]));
    vc = c;
    try {
      await c.initialize();
    } catch (e) {
      error = '$e';
    }
    c.addListener(() {
      if (!mounted) return;
      final p = c.value.position;
      // loop inside trim range
      if (m == VM.trim || m == VM.mp3) {
        final end = Duration(milliseconds: (dur.inMilliseconds * r1).round());
        if (c.value.isPlaying && p >= end) {
          c.seekTo(Duration(milliseconds: (dur.inMilliseconds * r0).round()));
        }
      }
      setState(() {
        pos = p;
        playing = c.value.isPlaying;
      });
    });
    if (m == VM.speed) await c.setPlaybackSpeed(speed.clamp(0.25, 4).toDouble());
    if (mounted) setState(() {});
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: !single);
    if (r == null) return;
    for (final f in r.files) {
      if (f.path != null) {
        if (single) {
          ins.clear();
          names.clear();
        }
        ins.add(f.path!);
        names.add(f.name);
      }
    }
    cur = single ? 0 : ins.length - 1;
    out = null;
    error = null;
    showOut = false;
    r0 = 0;
    r1 = 1;
    await oc?.dispose();
    oc = null;
    await _load(cur);
  }

  Future<void> pickWm() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final b = r?.files.single.bytes;
    if (b == null) return;
    final im = await decodeUi(b);
    cc.layers.removeWhere((l) => l.kind == LKind.image);
    cc.add(Layer(LKind.image, bytes: b, img: im, size: 0.2, aspect: im.height / im.width, dx: 0.85, dy: 0.88));
  }

  // ---- build FFmpeg args ----
  Future<List<String>> buildArgs(Directory tmp, {Duration? from}) async {
    final i0 = ins[cur];
    final a = r0 * dur.inMilliseconds / 1000, b = r1 * dur.inMilliseconds / 1000;
    final even = 'scale=trunc(iw/2)*2:trunc(ih/2)*2';
    switch (m) {
      case VM.crop:
        final w = rect.width, h = rect.height;
        return ['-i', i0, '-vf', 'crop=iw*$w:ih*$h:iw*${rect.left}:ih*${rect.top},$even', ...enc];
      case VM.blur:
        final lim = limitTime ? ":enable='between(t,${secs(a)},${secs(b)})'" : '';
        if (blurTarget == 0) {
          return ['-i', i0, '-vf', 'boxblur=${blurR.round()}:3', ...enc];
        }
        final cropS = 'crop=iw*${rect.width}:ih*${rect.height}:iw*${rect.left}:ih*${rect.top}';
        final mask = ellipse
            ? ",format=yuva420p,geq=lum='p(X,Y)':cb='p(X,Y)':cr='p(X,Y)':a='if(lte(pow((X-W/2)/(W/2),2)+pow((Y-H/2)/(H/2),2),1),255,0)'"
            : '';
        return [
          '-i', i0, '-filter_complex',
          '[0:v]split[a][b];[b]$cropS,boxblur=${blurR.round()}:3$mask[c];[a][c]overlay=main_w*${rect.left}:main_h*${rect.top}$lim',
          ...enc
        ];
      case VM.wmRemove:
        if (delogoIdx == 0) {
          final W = vsize.width, H = vsize.height;
          final x = math.max(1, (rect.left * W).round()), y = math.max(1, (rect.top * H).round());
          final w = math.min((rect.width * W).round(), W.round() - x - 1), h = math.min((rect.height * H).round(), H.round() - y - 1);
          return ['-i', i0, '-vf', 'delogo=x=$x:y=$y:w=$w:h=$h', ...enc];
        }
        return [
          '-i', i0, '-filter_complex',
          '[0:v]split[a][b];[b]crop=iw*${rect.width}:ih*${rect.height}:iw*${rect.left}:ih*${rect.top},boxblur=16:4[c];[a][c]overlay=main_w*${rect.left}:main_h*${rect.top}',
          ...enc
        ];
      case VM.trim:
        if (trimFast == 1) return ['-ss', secs(a), '-to', secs(b), '-i', i0, '-c', 'copy'];
        return ['-ss', secs(a), '-to', secs(b), '-i', i0, ...enc];
      case VM.mp3:
        return ['-ss', secs(a), '-to', secs(b), '-i', i0, '-vn', '-c:a', 'libmp3lame', '-b:a', '${[128, 192, 256, 320][mp3Rate]}k'];
      case VM.enhance:
        final f = <String>[
          if (denoise > 0) 'hqdn3d=${1.2 * denoise}:${1.2 * denoise}:${5 * denoise}:${5 * denoise}',
          if (up == 1) 'scale=iw*2:ih*2:flags=lanczos',
          'eq=contrast=$eqC:saturation=$eqS:brightness=$eqB',
          'unsharp=5:5:${sharp.toStringAsFixed(2)}:5:5:0.0',
          even,
        ];
        return ['-i', i0, '-vf', f.join(','), ...enc, '-crf', '16'];
      case VM.merge:
        final n = ins.length;
        final f = StringBuffer();
        for (var i = 0; i < n; i++) {
          f.write('[$i:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v$i];');
          f.write('[$i:a]aformat=sample_rates=44100:channel_layouts=stereo[a$i];');
        }
        for (var i = 0; i < n; i++) {
          f.write('[v$i][a$i]');
        }
        f.write('concat=n=$n:v=1:a=1[v][a]');
        return [for (final i in ins) ...['-i', i], '-filter_complex', f.toString(), '-map', '[v]', '-map', '[a]', ...enc];
      case VM.flip:
        return ['-i', i0, '-vf', ['hflip', 'vflip', 'transpose=1', 'hflip,vflip', 'transpose=2'][flipIdx], ...enc];
      case VM.speed:
        return ['-i', i0, '-vf', 'setpts=PTS/$speed', '-af', atempo(speed).join(','), ...enc];
      case VM.frame:
        final sz = [(1920, 1080), (1080, 1920), (1080, 1080), (1080, 1350)][frameA];
        final w = sz.$1, h = sz.$2;
        if (frameBg == 0) {
          return ['-i', i0, '-vf', 'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1', ...enc];
        }
        return [
          '-i', i0, '-filter_complex',
          '[0:v]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,boxblur=20:5[bg];[0:v]scale=$w:$h:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2,setsar=1',
          ...enc
        ];
      case VM.convert:
        switch (['mp4', 'mkv', 'webm', 'avi', 'mov', 'gif'][convIdx]) {
          case 'webm':
            return ['-i', i0, '-c:v', 'libvpx-vp9', '-crf', '32', '-b:v', '0', '-c:a', 'libopus'];
          case 'avi':
            return ['-i', i0, '-c:v', 'mpeg4', '-q:v', '3', '-c:a', 'libmp3lame'];
          case 'gif':
            return ['-i', i0, '-vf', 'fps=12,scale=480:-1:flags=lanczos', '-an'];
          default:
            return ['-i', i0, ...enc];
        }
      case VM.compress:
        final h = [0, 1080, 720, 480][hIdx];
        return [
          '-i', i0, if (h > 0) ...['-vf', 'scale=-2:$h'],
          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '${crf.round()}',
          '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k'
        ];
      case VM.text:
      case VM.wm:
        final W = (vsize.width / 2).round() * 2, H = (vsize.height / 2).round() * 2;
        final png = await renderLayers(cc, W, H);
        final f = File('${tmp.path}${Platform.pathSeparator}ov.png');
        await f.writeAsBytes(png);
        final lim = limitTime ? ":enable='between(t,${secs(a)},${secs(b)})'" : '';
        return ['-i', i0, '-i', f.path, '-filter_complex', '[0:v][1:v]overlay=0:0$lim,format=yuv420p', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-c:a', 'copy'];
    }
  }

  int blurTarget = 1; // 0 whole video, 1 region

  String get ext => switch (m) {
        VM.mp3 => 'mp3',
        VM.convert => ['mp4', 'mkv', 'webm', 'avi', 'mov', 'gif'][convIdx],
        _ => 'mp4',
      };

  Future<void> run({required bool preview}) async {
    if (ins.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      estimate = null;
    });
    try {
      final tmp = await Directory.systemTemp.createTemp('me_');
      var args = await buildArgs(tmp);
      if (preview && single && m != VM.trim && m != VM.mp3) {
        final start = secs(pos.inMilliseconds / 1000);
        final k = args.indexOf('-i');
        args = [...args.sublist(0, k), '-ss', start, ...args.sublist(k), '-t', '6'];
      }
      final o = '${tmp.path}${Platform.pathSeparator}out.$ext';
      await runFfmpeg(args, o);
      await oc?.dispose();
      oc = null;
      if (ext != 'mp3') {
        oc = VideoPlayerController.file(File(o));
        await oc!.initialize();
      }
      final size = File(o).lengthSync();
      if (mounted) {
        setState(() {
          out = o;
          outExt = ext;
          showOut = true;
          if (preview && m == VM.compress) {
            estimate = '${(size / 6 * dur.inSeconds / 1048576).toStringAsFixed(1)} MB';
          }
        });
        oc?.play();
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
    final p = await saveFileCopy(o, '${baseName(names.isEmpty ? 'video' : names[cur])}_edited.$outExt');
    if (p != null && mounted) toast(context, t(context, 'تم الحفظ', 'Saved'));
  }

  // ---- live preview effects ----
  Widget _transformed(Widget child) {
    if (m == VM.flip) {
      switch (flipIdx) {
        case 0:
          return Transform.scale(scaleX: -1, child: child);
        case 1:
          return Transform.scale(scaleY: -1, child: child);
        case 2:
          return RotatedBox(quarterTurns: 1, child: child);
        case 3:
          return RotatedBox(quarterTurns: 2, child: child);
        default:
          return RotatedBox(quarterTurns: 3, child: child);
      }
    }
    if (m == VM.enhance && !showOut) {
      final c = eqC, s = eqS, b = eqB * 255;
      const lr = 0.2126, lg = 0.7152, lb = 0.0722;
      final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
      final t0 = 128 * (1 - c) + b;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix([
          c * (sr + s), c * sg, c * sb, 0, t0,
          c * sr, c * (sg + s), c * sb, 0, t0,
          c * sr, c * sg, c * (sb + s), 0, t0,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      );
    }
    return child;
  }

  Widget stage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = showOut && oc != null ? oc : vc;
    Widget body;
    if (ctrl == null || !ctrl.value.isInitialized) {
      body = AspectRatio(
        aspectRatio: 16 / 9,
        child: InkWell(
          onTap: pick,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.video_library_outlined, size: 48, color: cs.primary),
            const SizedBox(height: 8),
            Text(t(context, 'اضغط لاختيار فيديو', 'Tap to choose a video')),
          ])),
        ),
      );
      if (showOut && out != null && ext == 'mp3') {
        body = AspectRatio(aspectRatio: 16 / 9, child: Center(child: Text(t(context, 'تم إنشاء ملف الصوت', 'Audio file created'))));
      }
    } else {
      final ar = ctrl.value.aspectRatio == 0 ? 16 / 9 : ctrl.value.aspectRatio;
      final video = VideoPlayer(ctrl);
      Widget inner;
      if (m == VM.frame && !showOut) {
        final fr = [16 / 9, 9 / 16, 1.0, 4 / 5][frameA];
        inner = AspectRatio(
          aspectRatio: fr,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Colors.black),
            if (frameBg == 1)
              ClipRect(
                  child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: ctrl.value.size.width, height: ctrl.value.size.height, child: VideoPlayer(ctrl))))),
            Center(child: AspectRatio(aspectRatio: ar, child: video)),
          ]),
        );
      } else {
        inner = AspectRatio(
          aspectRatio: (m == VM.flip && !showOut && (flipIdx == 2 || flipIdx == 4)) ? 1 / ar : ar,
          child: Stack(children: [
            Positioned.fill(child: _transformed(video)),
            if (!showOut && (m == VM.crop || m == VM.wmRemove || (m == VM.blur && blurTarget == 1)))
              Positioned.fill(
                  child: RegionBox(
                      rect: rect,
                      videoAspect: vaspect,
                      pixelRatio: m == VM.crop ? [null, 1.0, 16 / 9, 9 / 16, 4 / 3, 3 / 4, vaspect][ratioIdx] : null,
                      ellipse: m == VM.blur && ellipse,
                      dim: m == VM.crop,
                      onChanged: (r) => setState(() => rect = r))),
            if (!showOut && (m == VM.text || m == VM.wm))
              Positioned.fill(child: ComposerCanvas(cc: cc, aspect: ar, base: const SizedBox.shrink())),
          ]),
        );
      }
      body = ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(color: Colors.black, child: Center(child: inner)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      body,
      if (ctrl != null && ctrl.value.isInitialized) _controls(context, ctrl),
      if (out != null && oc != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Segs(
              items: [('الأصلي', 'Original'), ('النتيجة', 'Result')],
              sel: showOut ? 1 : 0,
              onChanged: (i) async {
                await vc?.pause();
                await oc?.pause();
                setState(() => showOut = i == 1);
              }),
        ),
    ]);
  }

  Widget _controls(BuildContext context, VideoPlayerController c) {
    final d = c.value.duration.inMilliseconds.toDouble();
    final p = c.value.position.inMilliseconds.toDouble().clamp(0.0, d == 0 ? 1.0 : d).toDouble();
    final range = (m == VM.trim || m == VM.mp3 || limitTime) && !showOut;
    return Column(children: [
      Row(children: [
        IconButton(
            icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 36),
            onPressed: () => c.value.isPlaying ? c.pause() : c.play()),
        Expanded(
            child: Slider(
                value: p,
                min: 0,
                max: d == 0 ? 1 : d,
                onChanged: (v) => c.seekTo(Duration(milliseconds: v.round())))),
        Text('${clock(c.value.position)} / ${clock(c.value.duration)}', style: const TextStyle(fontSize: 12)),
      ]),
      if (range) ...[
        RangeSlider(
            values: RangeValues(r0, r1),
            onChanged: (v) => setState(() {
                  r0 = v.start;
                  r1 = v.end;
                })),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton.icon(
              icon: const Icon(Icons.first_page, size: 18),
              label: Text('${t(context, 'البداية', 'Start')} ${clock(Duration(milliseconds: (d * r0).round()))}'),
              onPressed: d == 0 ? null : () => setState(() => r0 = math.min(p / d, r1 - 0.001))),
          TextButton.icon(
              icon: const Icon(Icons.last_page, size: 18),
              label: Text('${t(context, 'النهاية', 'End')} ${clock(Duration(milliseconds: (d * r1).round()))}'),
              onPressed: d == 0 ? null : () => setState(() => r1 = math.max(p / d, r0 + 0.001))),
        ]),
      ],
    ]);
  }

  // ---- options per tool ----
  List<Widget> options(BuildContext context) {
    switch (m) {
      case VM.crop:
        return [
          Panel(title: t(context, 'نسبة القص', 'Crop ratio'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Segs(items: [('حر', 'Free'), ('1:1', '1:1'), ('16:9', '16:9'), ('9:16', '9:16'), ('4:3', '4:3'), ('3:4', '3:4'), ('الأصلية', 'Original')], sel: ratioIdx, onChanged: (i) => setState(() {
              ratioIdx = i;
              final pr = [null, 1.0, 16 / 9, 9 / 16, 4 / 3, 3 / 4, vaspect][i];
              if (pr != null) {
                final w = 0.6, h = w * vaspect / pr;
                rect = h <= 1 ? Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h) : Rect.fromLTWH(0.3, 0, 0.4 * 1 / h, 1);
              }
            })),
            const SizedBox(height: 6),
            Text(t(context, 'اسحب الإطار فوق الفيديو لتحديد الجزء، واسحب الزوايا لتغيير الحجم.', 'Drag the frame over the video; drag corners to resize.'), style: const TextStyle(fontSize: 12)),
          ])),
        ];
      case VM.blur:
        return [
          Panel(title: t(context, 'التمويه', 'Blur'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Segs(items: [('كل الفيديو', 'Whole video'), ('منطقة محددة', 'Selected area')], sel: blurTarget, onChanged: (i) => setState(() => blurTarget = i)),
            if (blurTarget == 1) ...[
              const SizedBox(height: 6),
              Segs(items: [('مستطيل', 'Rectangle'), ('بقعة دائرية', 'Spot (oval)')], sel: ellipse ? 1 : 0, onChanged: (i) => setState(() => ellipse = i == 1)),
            ],
            Sld(t(context, 'قوة التمويه', 'Strength'), blurR, 2, 40, (v) => setState(() => blurR = v), divisions: 38),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'حصر التمويه في المقطع المحدد زمنيًا', 'Only during selected time range')), value: limitTime, onChanged: (v) => setState(() => limitTime = v)),
          ])),
        ];
      case VM.wmRemove:
        return [
          Panel(title: t(context, 'إزالة العلامة المائية', 'Watermark removal'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(context, 'ضع الإطار فوق العلامة المائية بالضبط.', 'Place the frame exactly over the watermark.'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Segs(items: [('ترميم (أفضل)', 'Inpaint (best)'), ('تمويه', 'Blur')], sel: delogoIdx, onChanged: (i) => setState(() => delogoIdx = i)),
          ])),
        ];
      case VM.trim:
        return [
          Panel(title: t(context, 'القص', 'Trim'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(context, 'حرّك المقبضين تحت الفيديو لتحديد البداية والنهاية.', 'Move the two handles under the video to set start and end.'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Segs(items: [('دقيق (إعادة ترميز)', 'Exact (re-encode)'), ('سريع (بدون فقدان)', 'Fast (no quality loss)')], sel: trimFast, onChanged: (i) => setState(() => trimFast = i)),
          ])),
        ];
      case VM.mp3:
        return [
          Panel(title: t(context, 'الصوت', 'Audio'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(context, 'حدد الجزء المراد تحويله بالمقبضين تحت الفيديو.', 'Select the part to convert with the handles.'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Segs(items: [('128k', '128k'), ('192k', '192k'), ('256k', '256k'), ('320k', '320k')], sel: mp3Rate, onChanged: (i) => setState(() => mp3Rate = i)),
          ])),
        ];
      case VM.enhance:
        return [
          Panel(title: t(context, 'التحسين', 'Enhance'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, children: [
              ActionChip(label: Text(t(context, 'تلقائي متوازن', 'Auto balanced')), onPressed: () => setState(() { eqC = 1.1; eqS = 1.15; eqB = 0.02; sharp = 1.0; denoise = 1; })),
              ActionChip(label: Text(t(context, 'إضاءة ضعيفة', 'Low light')), onPressed: () => setState(() { eqC = 1.2; eqS = 1.1; eqB = 0.1; sharp = 0.8; denoise = 2; })),
              ActionChip(label: Text(t(context, 'حدة عالية', 'Extra sharp')), onPressed: () => setState(() { eqC = 1.08; eqS = 1.1; eqB = 0; sharp = 1.8; denoise = 0.5; })),
            ]),
            Sld(t(context, 'التباين', 'Contrast'), eqC, 0.8, 1.5, (v) => setState(() => eqC = v)),
            Sld(t(context, 'التشبع', 'Saturation'), eqS, 0.5, 1.8, (v) => setState(() => eqS = v)),
            Sld(t(context, 'السطوع', 'Brightness'), eqB, -0.2, 0.3, (v) => setState(() => eqB = v)),
            Sld(t(context, 'الحدة', 'Sharpness'), sharp, 0, 2.5, (v) => setState(() => sharp = v)),
            Sld(t(context, 'إزالة التشويش', 'Denoise'), denoise, 0, 3, (v) => setState(() => denoise = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'تكبير الدقة ×2 (أبطأ)', 'Upscale ×2 (slower)')), value: up == 1, onChanged: (v) => setState(() => up = v ? 1 : 0)),
            Text(t(context, 'الألوان تظهر مباشرة في المعاينة، أما الحدة وإزالة التشويش فتظهر بزر المعاينة السريعة.', 'Colour changes show live; sharpness/denoise show with Quick preview.'), style: const TextStyle(fontSize: 12)),
          ])),
        ];
      case VM.merge:
        return [
          Panel(title: t(context, 'المقاطع', 'Clips'), child: Column(children: [
            if (ins.isEmpty) Text(t(context, 'أضف مقطعين أو أكثر', 'Add two or more clips')),
            for (var i = 0; i < ins.length; i++)
              ListTile(
                dense: true,
                selected: cur == i,
                leading: Text('${i + 1}'),
                title: Text(names[i], overflow: TextOverflow.ellipsis),
                onTap: () async { cur = i; await _load(i); },
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.arrow_upward, size: 18), onPressed: i == 0 ? null : () => setState(() { ins.insert(i - 1, ins.removeAt(i)); names.insert(i - 1, names.removeAt(i)); })),
                  IconButton(icon: const Icon(Icons.arrow_downward, size: 18), onPressed: i == ins.length - 1 ? null : () => setState(() { ins.insert(i + 1, ins.removeAt(i)); names.insert(i + 1, names.removeAt(i)); })),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () async { ins.removeAt(i); names.removeAt(i); cur = 0; if (ins.isNotEmpty) { await _load(0); } else { await vc?.dispose(); vc = null; } setState(() {}); }),
                ]),
              ),
          ])),
        ];
      case VM.flip:
        return [
          Panel(title: t(context, 'القلب والتدوير', 'Flip / rotate'), child: Segs(items: [('قلب أفقي', 'Flip H'), ('قلب عمودي', 'Flip V'), ('تدوير 90°', 'Rotate 90°'), ('تدوير 180°', 'Rotate 180°'), ('تدوير 270°', 'Rotate 270°')], sel: flipIdx, onChanged: (i) => setState(() => flipIdx = i))),
        ];
      case VM.speed:
        return [
          Panel(title: t(context, 'السرعة', 'Speed'), child: Column(children: [
            Sld(t(context, 'السرعة', 'Speed'), speed, 0.25, 4, (v) { setState(() => speed = v); vc?.setPlaybackSpeed(v); }, divisions: 15, fmt: (v) => '×${v.toStringAsFixed(2)}'),
            Text(t(context, 'المعاينة تُشغَّل بالسرعة المختارة مباشرة.', 'Preview plays at the chosen speed.'), style: const TextStyle(fontSize: 12)),
          ])),
        ];
      case VM.frame:
        return [
          Panel(title: t(context, 'إطار الفيديو', 'Frame'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Segs(items: [('16:9', '16:9'), ('9:16', '9:16'), ('1:1', '1:1'), ('4:5', '4:5')], sel: frameA, onChanged: (i) => setState(() => frameA = i)),
            const SizedBox(height: 6),
            Segs(items: [('أسود', 'Black bars'), ('تمويه الخلفية', 'Blurred background')], sel: frameBg, onChanged: (i) => setState(() => frameBg = i)),
          ])),
        ];
      case VM.convert:
        return [Panel(title: t(context, 'الصيغة', 'Format'), child: Segs(items: [for (final f in ['MP4', 'MKV', 'WEBM', 'AVI', 'MOV', 'GIF']) (f, f)], sel: convIdx, onChanged: (i) => setState(() => convIdx = i)))];
      case VM.compress:
        return [
          Panel(title: t(context, 'الضغط', 'Compression'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Sld(t(context, 'مستوى الضغط (أعلى = أصغر)', 'Level (higher = smaller)'), crf, 18, 38, (v) => setState(() => crf = v), divisions: 20),
            Segs(items: [('الدقة الأصلية', 'Original'), ('1080p', '1080p'), ('720p', '720p'), ('480p', '480p')], sel: hIdx, onChanged: (i) => setState(() => hIdx = i)),
            if (estimate != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${t(context, 'الحجم المتوقع تقريبًا', 'Estimated size')}: $estimate', style: const TextStyle(fontWeight: FontWeight.w700))),
          ])),
        ];
      case VM.text:
      case VM.wm:
        return [
          if (m == VM.wm)
            Panel(child: OutlinedButton.icon(onPressed: pickWm, icon: const Icon(Icons.image_outlined), label: Text(t(context, 'اختيار صورة العلامة', 'Choose watermark image')))),
          ComposerPanel(cc: cc, kinds: m == VM.text ? {LKind.text} : {LKind.text, LKind.image}),
          Panel(child: SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t(context, 'إظهارها فقط في المقطع المحدد زمنيًا', 'Show only in the selected time range')), value: limitTime, onChanged: (v) => setState(() => limitTime = v))),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final canQuick = single && m != VM.trim && m != VM.mp3 && m != VM.convert;
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.tonalIcon(
            onPressed: pick,
            icon: const Icon(Icons.folder_open),
            label: Text(single ? t(context, 'اختيار فيديو', 'Choose video') : t(context, 'إضافة مقاطع', 'Add clips'))),
        if (single && names.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(names.first, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
      ])),
      ...options(context),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (canQuick) ...[
          BusyButton(t(context, 'معاينة سريعة (6 ثوانٍ)', 'Quick preview (6 s)'), busy: busy, tonal: true, onTap: ins.isEmpty ? null : () => run(preview: true)),
          const SizedBox(height: 8),
        ],
        BusyButton(t(context, 'تنفيذ على كامل الفيديو', 'Run on full video'), busy: busy, onTap: ins.length < (single ? 1 : 2) ? null : () => run(preview: false)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: out == null ? null : save, icon: const Icon(Icons.save_alt), label: Text(t(context, 'حفظ', 'Save'))),
        if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        if (out != null && !busy) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${t(context, 'تم', 'Done')} - ${(File(out!).lengthSync() / 1048576).toStringAsFixed(2)} MB', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
      ])),
    ]);
    return StudioLayout(stage: stage(context), side: side);
  }
}
