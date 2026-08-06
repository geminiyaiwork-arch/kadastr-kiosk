import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FON YUZ-TANISH — O'CHIRILDI (2026-08-06, user talabi: «o'zidan o'zi gapirmasin;
/// faqat "Alomat / Alomatxon" deb chaqirilганда buyruq qabul qilsin»).
///
/// Avval bu widget har ~4 soniyada kamera kadrini olib, ODAM ko'rinса — SO'RALMASДАН
/// o'zidan salomlashib turardi (spontan gap) VA kadrlarни `Pictures` papkasiga
/// to'plардi (disk to'lardi). Ikkovi ham foydalanuvchiни bezovta qilardi.
///
/// ENDI: periodik kamera-olish + avto-salomlashuv BUTUNLAY o'chirilди — kiosk faqat
/// "Alomat" wake-so'ziда uyg'onadi (voice_controller). Bu widget endi FAQAT ilova
/// ochilишда eski `PhotoCapture_*.jpeg` backlogни bir marta tozalaydi (disk bo'shasin).
/// («Meni eslab qol» yuz-ro'yxати alohida `face_enroll_screen` orqali, foydalanuvchi
///  o'zi bosганда ishlaydi — fon-tanish bilan bog'liq emas.)
class FaceWatchHost extends ConsumerStatefulWidget {
  const FaceWatchHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<FaceWatchHost> createState() => _FaceWatchHostState();
}

class _FaceWatchHostState extends ConsumerState<FaceWatchHost> {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _cleanupBacklog(); // eski PhotoCapture_*.jpeg to'plamини tozalash
  }

  /// Eski fon-kadrlar (PhotoCapture_*.jpeg) Pictures/temp papkasiga to'planиб qolган
  /// bo'lса — bir marta tozalaymiz (disk to'lган edi). Yangi kadr endi UMUMAN olinmaydi.
  Future<void> _cleanupBacklog() async {
    try {
      final dirs = <String>[];
      final up = Platform.environment['USERPROFILE'];
      if (up != null) dirs.add('$up\\Pictures');
      try { dirs.add(Directory.systemTemp.path); } catch (_) {}
      for (final dp in dirs) {
        final d = Directory(dp);
        if (!d.existsSync()) continue;
        for (final e in d.listSync()) {
          if (e is File && e.path.contains('PhotoCapture_')) {
            try { e.deleteSync(); } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
