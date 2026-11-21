import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'strings.dart';

/// Runs [fn] in an isolate. Always pass a top-level function and a plain
/// argument so no UI object is captured by the closure.
Future<R> runIso<A, R>(FutureOr<R> Function(A) fn, A arg) =>
    Isolate.run<R>(() => fn(arg));

String clock(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final t = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
  final h = d.inHours > 0 ? '${d.inHours}:' : '';
  return '$h$m:$s.$t';
}

String secs(double s) => s.toStringAsFixed(3);

Future<String> tmpFile(String name) async {
  final d = await Directory.systemTemp.createTemp('me_');
  return '${d.path}${Platform.pathSeparator}$name';
}

/// Save a file that already exists on disk.
Future<String?> saveFileCopy(String src, String name) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return FilePicker.platform
        .saveFile(fileName: name, bytes: await File(src).readAsBytes());
  }
  final p = await FilePicker.platform.saveFile(fileName: name);
  if (p != null) await File(src).copy(p);
  return p;
}

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

// ---------- shared UI ----------
class Panel extends StatelessWidget {
  final String? title;
  final Widget child;
  const Panel({super.key, this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              Text(title!,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
            ],
            child,
          ]),
        ),
      );
}

/// Stage (preview) + side panel. Side by side on wide screens.
class StudioLayout extends StatelessWidget {
  final Widget stage, side;
  const StudioLayout({super.key, required this.stage, required this.side});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 900) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(child: stage)),
              const SizedBox(width: 16),
              SizedBox(width: 380, child: SingleChildScrollView(child: side)),
            ]),
          );
        }
        return ListView(padding: const EdgeInsets.all(12), children: [stage, const SizedBox(height: 4), side]);
      });
}

class Segs extends StatelessWidget {
  final List<(String, String)> items;
  final int sel;
  final ValueChanged<int> onChanged;
  const Segs({super.key, required this.items, required this.sel, required this.onChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < items.length; i++)
          ChoiceChip(
              label: Text(t(context, items[i].$1, items[i].$2)),
              selected: sel == i,
              onSelected: (_) => onChanged(i)),
      ]);
}

class Sld extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int? divisions;
  final String Function(double)? fmt;
  final ValueChanged<double> onChanged;
  const Sld(this.label, this.value, this.min, this.max, this.onChanged,
      {super.key, this.divisions, this.fmt});
  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ${fmt != null ? fmt!(value) : value.toStringAsFixed(max <= 5 ? 2 : 0)}'),
            Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged),
          ]);
}

class BusyButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback? onTap;
  final bool tonal;
  const BusyButton(this.label, {super.key, required this.busy, this.onTap, this.tonal = false});
  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Text(label);
    return tonal
        ? FilledButton.tonal(onPressed: busy ? null : onTap, child: child)
        : FilledButton(onPressed: busy ? null : onTap, child: child);
  }
}

const palette = <Color>[
  Colors.white, Colors.black, Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835),
  Color(0xFF43A047), Color(0xFF00ACC1), Color(0xFF1E88E5), Color(0xFF8E24AA),
  Color(0xFFEC407A), Color(0xFF6D4C41), Color(0xFF90A4AE),
];

/// Swatches plus a full HSV picker.
class ColorPick extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const ColorPick({super.key, required this.color, required this.onChanged});
  @override
  State<ColorPick> createState() => _ColorPickState();
}

class _ColorPickState extends State<ColorPick> {
  bool custom = false;
  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(widget.color);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in palette)
          GestureDetector(
            onTap: () => widget.onChanged(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: widget.color.toARGB32() == c.toARGB32()
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withAlpha(120),
                      width: widget.color.toARGB32() == c.toARGB32() ? 3 : 1)),
            ),
          ),
        ActionChip(
            avatar: const Icon(Icons.colorize, size: 16),
            label: Text(t(context, 'مخصص', 'Custom')),
            onPressed: () => setState(() => custom = !custom)),
      ]),
      if (custom) ...[
        Slider(
            value: hsv.hue,
            min: 0,
            max: 359,
            onChanged: (v) => widget.onChanged(hsv.withHue(v).toColor())),
        Slider(
            value: hsv.saturation,
            min: 0,
            max: 1,
            onChanged: (v) => widget.onChanged(hsv.withSaturation(v).toColor())),
        Slider(
            value: hsv.value,
            min: 0,
            max: 1,
            onChanged: (v) => widget.onChanged(hsv.withValue(v).toColor())),
      ],
    ]);
  }
}
