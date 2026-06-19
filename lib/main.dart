import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const opts = WindowOptions(
    size: Size(560, 1000), // dev window; real kiosk = fullscreen (M5)
    center: true,
    title: 'Davlat Kadastrlari Palatasi — Kiosk',
    backgroundColor: Color(0xFF0C1430),
  );
  unawaited(windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.show();
    await windowManager.focus();
    // M5 kiosk lockdown:
    // await windowManager.setFullScreen(true);
    // await windowManager.setAlwaysOnTop(true);
    // await windowManager.setPreventClose(true);
  }));

  runApp(const ProviderScope(child: KioskApp()));
}
