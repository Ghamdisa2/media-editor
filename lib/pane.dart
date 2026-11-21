import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'strings.dart';

String fmt(double s) {
  final m = s ~/ 60, x = s - m * 60;
  return '${m.toString().padLeft(2, '0')}:${x.toStringAsFixed(1).padLeft(4, '0')}';
}

/// Player wrapper shared by every video/audio tool.
class Pane extends ChangeNotifier {
  final Player player = Player();
  late final VideoController vc = VideoController(player);
  Size vsize = Size.zero;
  Duration pos = Duration.zero, dur = Duration.zero;
  bool playing = false, _dead = false;
  final _subs = <StreamSubscription>[];

  Pane() {
    _subs.addAll([
      player.stream.width.listen((w) { vsize = Size((w ?? 0).toDouble(), vsize.height); _n(); }),
      player.stream.height.listen((h) { vsize = Size(vsize.width, (h ?? 0).toDouble()); _n(); }),
      player.stream.position.listen((p) { pos = p; _n(); }),
      player.stream.duration.listen((d) { dur = d; _n(); }),
      player.stream.playing.listen((p) { playing = p; _n(); }),
    ]);
  }
  void _n() {
    if (!_dead) notifyListeners();
  }

  double get seconds => dur.inMilliseconds / 1000.0;
  double get seconds_pos => pos.inMilliseconds / 1000.0;
  Future<void> open(String path) => player.open(Media(path), play: false);
  Future<void> seekTo(double s) => player.seek(Duration(milliseconds: (s * 1000).round()));

  @override
  void dispose() {
    _dead = true;
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

class MediaPane extends StatelessWidget {
  final Pane pane;
  final bool audio, hasMedia;
  final Widget Function(Size)? overlay;
  const MediaPane({super.key, required this.pane, required this.hasMedia, this.audio = false, this.overlay});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: pane,
      builder: (_, __) {
        final secs = pane.seconds;
        final cur = math.min(pane.seconds_pos, math.max(secs, 0.1));
        Widget area;
        if (!hasMedia) {
          area = Center(child: Text(t(context, 'اختر ملفًا للبدء', 'Choose a file to start')));
        } else if (audio) {
          area = Center(child: Icon(Icons.graphic_eq, size: 64, color: cs.primary));
        } else {
          area = LayoutBuilder(builder: (_, c) {
            final vs = pane.vsize;
            final ar = (vs.width > 0 && vs.height > 0) ? vs.width / vs.height : 16 / 9;
            final fit = applyBoxFit(BoxFit.contain, Size(ar, 1), c.biggest).destination;
            return Center(
              child: SizedBox(
                width: fit.width,
                height: fit.height,
                child: Stack(fit: StackFit.expand, children: [
                  Video(controller: pane.vc, controls: NoVideoControls),
                  if (overlay != null) overlay!(fit),
                ]),
              ),
            );
          });
        }
        return Column(children: [
          Expanded(
              child: Container(
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  child: area)),
          if (hasMedia)
            Row(children: [
              IconButton(
                  onPressed: () => pane.player.playOrPause(),
                  icon: Icon(pane.playing ? Icons.pause : Icons.play_arrow)),
              Expanded(
                  child: Slider(
                      value: cur.clamp(0, math.max(secs, 0.1)).toDouble(),
                      min: 0,
                      max: math.max(secs, 0.1),
                      onChanged: (x) => pane.seekTo(x))),
              Text('${fmt(cur)} / ${fmt(secs)}', style: const TextStyle(fontSize: 12)),
            ]),
        ]);
      },
    );
  }
}

/// Draggable / resizable selection rectangle in fractions (0..1) of the video.
class RectEditor extends StatefulWidget {
  final Rect rect;
  final double? aspect; // pixel w/h, null = free
  final bool ellipse;
  final ValueChanged<Rect> onChanged;
  const RectEditor({super.key, required this.rect, required this.onChanged, this.aspect, this.ellipse = false});
  @override
  State<RectEditor> createState() => _RectEditorState();
}

class _RectEditorState extends State<RectEditor> {
  int mode = 0; // 1 move, 2 TL, 3 TR, 4 BL, 5 BR
  Offset cur = Offset.zero;
  Size S = Size.zero;

  Rect get px => Rect.fromLTRB(widget.rect.left * S.width, widget.rect.top * S.height,
      widget.rect.right * S.width, widget.rect.bottom * S.height);

  void start(Offset p) {
    cur = p;
    final r = px;
    final corners = {2: r.topLeft, 3: r.topRight, 4: r.bottomLeft, 5: r.bottomRight};
    mode = 0;
    for (final e in corners.entries) {
      if ((e.value - p).distance < 30) mode = e.key;
    }
    if (mode == 0 && r.contains(p)) mode = 1;
  }

  void update(Offset d) {
    if (S.width == 0 || mode == 0) return;
    cur += d;
    final r = widget.rect;
    if (mode == 1) {
      final dx = d.dx / S.width, dy = d.dy / S.height;
      final nx = (r.left + dx).clamp(0.0, 1 - r.width).toDouble(), ny = (r.top + dy).clamp(0.0, 1 - r.height).toDouble();
      widget.onChanged(Rect.fromLTWH(nx, ny, r.width, r.height));
      return;
    }
    final a = switch (mode) {
      2 => Offset(r.right, r.bottom),
      3 => Offset(r.left, r.bottom),
      4 => Offset(r.right, r.top),
      _ => Offset(r.left, r.top),
    };
    final p = Offset((cur.dx / S.width).clamp(0.0, 1.0).toDouble(), (cur.dy / S.height).clamp(0.0, 1.0).toDouble());
    final w = (p.dx - a.dx).abs();
    var h = (p.dy - a.dy).abs();
    if (widget.aspect != null) h = w * S.width / (widget.aspect! * S.height);
    final sx = (mode == 2 || mode == 4) ? -1 : 1;
    final sy = (mode == 2 || mode == 3) ? -1 : 1;
    final bx = a.dx + sx * w, by = a.dy + sy * h;
    if (bx < 0 || bx > 1 || by < 0 || by > 1 || w < 0.03 || h < 0.03) return;
    widget.onChanged(Rect.fromPoints(a, Offset(bx, by)));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        S = c.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => start(d.localPosition),
          onPanUpdate: (d) => update(d.delta),
          child: CustomPaint(size: S, painter: _RectPainter(px, widget.ellipse)),
        );
      });
}

class _RectPainter extends CustomPainter {
  final Rect r;
  final bool ellipse;
  _RectPainter(this.r, this.ellipse);
  @override
  void paint(Canvas c, Size s) {
    final all = Path()..addRect(Offset.zero & s);
    final hole = Path()..addRect(r);
    final sel = ellipse ? (Path()..addOval(r)) : hole;
    c.drawPath(Path.combine(PathOperation.difference, all, sel), Paint()..color = const Color(0x99000000));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    c.drawPath(sel, line);
    if (ellipse) c.drawRect(r, line..strokeWidth = 1);
    final h = Paint()..color = Colors.white;
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      c.drawRect(Rect.fromCenter(center: p, width: 14, height: 14), h);
    }
  }

  @override
  bool shouldRepaint(covariant _RectPainter o) => o.r != r || o.ellipse != ellipse;
}

/// Audio waveform picture with playhead and selected range.
class WaveBox extends StatelessWidget {
  final String? png;
  final Pane pane;
  final double start, end;
  const WaveBox({super.key, required this.png, required this.pane, required this.start, required this.end});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: pane,
      builder: (_, __) {
        final d = math.max(pane.seconds, 0.1);
        return Container(
          height: 120,
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (_, c) => GestureDetector(
              onTapDown: (t) => pane.seekTo(t.localPosition.dx / c.maxWidth * d),
              child: Stack(fit: StackFit.expand, children: [
                if (png != null) Image.file(File(png!), fit: BoxFit.fill) else const Center(child: CircularProgressIndicator()),
                CustomPaint(painter: _WavePainter(start / d, (end <= 0 ? d : end) / d, pane.seconds_pos / d, cs.primary)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double a, b, head;
  final Color color;
  _WavePainter(this.a, this.b, this.head, this.color);
  @override
  void paint(Canvas c, Size s) {
    final dim = Paint()..color = const Color(0x88000000);
    c.drawRect(Rect.fromLTRB(0, 0, a * s.width, s.height), dim);
    c.drawRect(Rect.fromLTRB(b * s.width, 0, s.width, s.height), dim);
    c.drawLine(Offset(head * s.width, 0), Offset(head * s.width, s.height), Paint()..color = Colors.white..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _WavePainter o) => true;
}
