import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const opts = WindowOptions(
    size: Size(560, 1000), // letterbox fallback size if fullscreen is unavailable
    center: true,
    title: 'Davlat Kadastrlari Palatasi — Kiosk',
    backgroundColor: Color(0xFF0C1430),
    titleBarStyle: TitleBarStyle.hidden,
  );
  unawaited(windowManager.waitUntilReadyToShow(opts, () async {
    // Kiosk = butun ekranni egallaydi. Avval shu sababli header tepadan
    // kesilardi (oyna 1000px, laptop ekrani undan past edi). Fullscreen →
    // header to'liq ko'rinadi + idle/attract butun ekranda. Chiqish: logoni
    // 10 marta bosib "Ilovadan chiqish" (operator menyu).
    try {
      await windowManager.setFullScreen(true);
    } catch (_) {}
    await windowManager.show();
    await windowManager.focus();
  }));

  runApp(const ProviderScope(child: KioskApp()));
}
