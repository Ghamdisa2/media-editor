import 'package:flutter/material.dart';

enum Cat { video, image, audio }

/// phase 0 = works now; 1+ = planned phase.
class Tool {
  final String id;
  final Cat cat;
  final IconData icon;
  final String ar, en;
  final int phase;
  const Tool(this.id, this.cat, this.icon, this.ar, this.en, [this.phase = 2]);
  bool get ready => phase == 0 || implemented.contains(id);
}

const tools = <Tool>[
  // Video (phase 2: FFmpeg)
  Tool('v_crop', Cat.video, Icons.crop, 'قص أبعاد الفيديو', 'Video Cropper'),
  Tool('v_blur', Cat.video, Icons.blur_on, 'تمويه الفيديو', 'Video Blur'),
  Tool('v_trim', Cat.video, Icons.content_cut, 'اقتطاع جزء من الفيديو', 'Video Trimmer'),
  Tool('v_enhance', Cat.video, Icons.auto_fix_high, 'تحسين الفيديو', 'Video Enhancer'),
  Tool('v_merge', Cat.video, Icons.call_merge, 'دمج مقاطع الفيديو', 'Video Merger'),
  Tool('v_mp3', Cat.video, Icons.audiotrack, 'فيديو إلى MP3', 'Video to MP3'),
  Tool('v_flip', Cat.video, Icons.flip, 'قلب الفيديو', 'Video Flipper'),
  Tool('v_speed', Cat.video, Icons.speed, 'تسريع وإبطاء الفيديو', 'Video Speeder'),
  Tool('v_frame', Cat.video, Icons.aspect_ratio, 'ضبط إطار الفيديو', 'Video Frame Adjuster'),
  Tool('v_convert', Cat.video, Icons.swap_horiz, 'تحويل صيغة الفيديو', 'Video Converter'),
  Tool('v_compress', Cat.video, Icons.compress, 'ضغط حجم الفيديو', 'Video Compressor'),
  Tool('v_text', Cat.video, Icons.text_fields, 'إضافة نص على الفيديو', 'Add Text to Video'),
  Tool('v_wm_add', Cat.video, Icons.branding_watermark, 'إضافة علامة مائية للفيديو', 'Add Watermark to Video'),
  Tool('v_wm_remove', Cat.video, Icons.hide_image, 'إزالة العلامة المائية من الفيديو', 'Watermark Remover', 3),
  // Image
  Tool('i_crop', Cat.image, Icons.crop, 'قص الصورة', 'Image Cropper', 1),
  Tool('i_blur', Cat.image, Icons.blur_on, 'تمويه الصورة', 'Image Blur', 0),
  Tool('i_enhance', Cat.image, Icons.auto_fix_high, 'تحسين الصورة', 'Image Enhancer', 0),
  Tool('i_merge', Cat.image, Icons.call_merge, 'دمج الصور', 'Images Merger', 0),
  Tool('i_collage', Cat.image, Icons.view_quilt, 'كولاج الصور', 'Images Collage', 1),
  Tool('i_blend', Cat.image, Icons.blur_linear, 'مزج الصور', 'Images Blender', 1),
  Tool('i_pdf', Cat.image, Icons.picture_as_pdf, 'صور متعددة إلى PDF', 'Multi Images to PDF', 0),
  Tool('i_flip', Cat.image, Icons.flip, 'قلب الصورة', 'Image Flipper', 0),
  Tool('i_bg', Cat.image, Icons.layers_clear, 'إزالة خلفية الصورة', 'Background Remover', 3),
  Tool('i_convert', Cat.image, Icons.swap_horiz, 'تحويل صيغة الصورة', 'Image Converter', 0),
  Tool('i_compress', Cat.image, Icons.compress, 'ضغط حجم الصورة', 'Image Compressor', 0),
  Tool('i_text', Cat.image, Icons.text_fields, 'إضافة نص على الصورة', 'Add Text to Image', 1),
  Tool('i_wm_add', Cat.image, Icons.branding_watermark, 'إضافة علامة مائية للصور', 'Add Watermark', 1),
  Tool('i_wm_design', Cat.image, Icons.draw, 'مصمم العلامات المائية', 'Watermark Designer', 4),
  Tool('i_logo', Cat.image, Icons.palette, 'مصمم الشعارات', 'Logo Designer', 4),
  // Audio
  Tool('a_merge', Cat.audio, Icons.call_merge, 'دمج الملفات الصوتية', 'Audio Merger'),
  Tool('a_mix', Cat.audio, Icons.tune, 'مزج الأصوات', 'Audio Mixer'),
  Tool('a_trim', Cat.audio, Icons.content_cut, 'اقتطاع جزء من الصوت', 'Audio Trimmer'),
  Tool('a_enhance', Cat.audio, Icons.graphic_eq, 'تحسين الصوت وإزالة الضجيج', 'Audio Enhancer', 3),
  Tool('a_speed', Cat.audio, Icons.speed, 'تسريع وإبطاء الصوت', 'Audio Speeder'),
  Tool('a_convert', Cat.audio, Icons.swap_horiz, 'تحويل صيغة الصوت', 'Audio Converter'),
  Tool('a_stt', Cat.audio, Icons.subtitles, 'الصوت إلى نص', 'Audio to Text', 3),
  Tool('a_tts', Cat.audio, Icons.record_voice_over, 'النص إلى صوت', 'Text to Audio', 3),
];

const implemented = <String>{
  'v_crop','v_blur','v_trim','v_enhance','v_merge','v_mp3','v_flip','v_speed','v_frame',
  'v_convert','v_compress','v_text','v_wm_add','v_wm_remove',
  'i_crop','i_collage','i_blend','i_text','i_wm_add',
  'a_merge','a_mix','a_trim','a_enhance','a_speed','a_convert',
};
