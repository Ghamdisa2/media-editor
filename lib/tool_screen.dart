import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'image_tools.dart';
import 'media_tools.dart';
import 'overlay_tool.dart';
import 'strings.dart';
import 'tools.dart';

/// Every tool opens in its own dedicated screen.
class ToolScreen extends StatelessWidget {
  final Tool tool;
  const ToolScreen({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (tool.id) {
      'i_flip' => ImageTool(opts: [
          Opt('dir', 'الاتجاه', 'Direction', 0, 2, 0,
              choices: const [
                ('أفقي', 'Horizontal'),
                ('عمودي', 'Vertical'),
                ('الاثنان', 'Both')
              ]),
        ], run: flipRun, ext: (_) => 'png', suffix: 'flipped'),
      'i_blur' => ImageTool(opts: [
          Opt('r', 'قوة التمويه', 'Blur radius', 1, 40, 8, divisions: 39),
        ], run: blurRun, ext: (_) => 'png', suffix: 'blur'),
      'i_enhance' => ImageTool(opts: [
          Opt('b', 'السطوع', 'Brightness', 0.5, 1.5, 1.05, divisions: 20),
          Opt('c', 'التباين', 'Contrast', 0.5, 1.5, 1.1, divisions: 20),
          Opt('s', 'التشبع', 'Saturation', 0.0, 2.0, 1.1, divisions: 20),
        ], run: enhanceRun, ext: (_) => 'png', suffix: 'enhanced'),
      'i_compress' => ImageTool(opts: [
          Opt('q', 'الجودة', 'Quality', 10, 100, 70, divisions: 90),
          Opt('w', 'تصغير الأبعاد %', 'Scale %', 10, 100, 100, divisions: 18),
        ], run: compressRun, ext: (_) => 'jpg', suffix: 'small'),
      'i_convert' => ImageTool(opts: [
          Opt('f', 'الصيغة', 'Format', 0, 2, 0, choices: const [
            ('JPG', 'JPG'),
            ('PNG', 'PNG'),
            ('BMP', 'BMP')
          ]),
        ], run: convertRun, ext: (v) => const ['jpg', 'png', 'bmp'][v['f']!.round()], suffix: 'converted'),
      'i_merge' => const MultiImageTool(mode: MultiMode.merge),
      'i_pdf' => const MultiImageTool(mode: MultiMode.pdf),
      'i_crop' => ImageTool(opts: [
          Opt('x', 'البداية أفقيًا %', 'Left %', 0, 95, 10, divisions: 95),
          Opt('y', 'البداية عموديًا %', 'Top %', 0, 95, 10, divisions: 95),
          Opt('w', 'العرض %', 'Width %', 5, 100, 80, divisions: 95),
          Opt('h', 'الارتفاع %', 'Height %', 5, 100, 80, divisions: 95),
        ], run: cropRun, ext: (_) => 'png', suffix: 'cropped'),
      'i_collage' => const MultiImageTool(mode: MultiMode.collage),
      'i_blend' => const MultiImageTool(mode: MultiMode.blend),
      'i_text' => const OverlayTool(watermark: false),
      'i_wm_add' => const OverlayTool(watermark: true),
      _ => ffmpegTool(tool.id) ?? ComingSoon(tool: tool),
    };
    return Scaffold(
      appBar: AppBar(title: Text(t(context, tool.ar, tool.en))),
      body: SafeArea(child: body),
    );
  }
}

class ComingSoon extends StatelessWidget {
  final Tool tool;
  const ComingSoon({super.key, required this.tool});
  @override
  Widget build(BuildContext context) {
    final msg = switch (tool.phase) {
      1 => ('المرحلة التالية: أدوات الصور التفاعلية', 'Next: interactive image tools'),
      2 => ('المرحلة 2: محرك FFmpeg للفيديو والصوت', 'Phase 2: FFmpeg video and audio engine'),
      3 => ('المرحلة 3: أدوات الذكاء الاصطناعي المحلية', 'Phase 3: on-device AI tools'),
      _ => ('المرحلة 4: مصمم الشعارات والعلامات', 'Phase 4: logo and watermark designer'),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(tool.icon, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(t(context, 'هذه الأداة قيد التطوير', 'This tool is in development'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(t(context, msg.$1, msg.$2)),
      ]),
    );
  }
}

/// Save bytes: Android via bytes param, desktop via save dialog then write.
Future<String?> saveBytes(String name, Uint8List bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return FilePicker.platform.saveFile(fileName: name, bytes: bytes);
  }
  final p = await FilePicker.platform.saveFile(fileName: name);
  if (p == null) return null;
  await File(p).writeAsBytes(bytes);
  return p;
}
