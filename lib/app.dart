import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/services/heartbeat.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'features/ai/ambient_voice_host.dart';
import 'features/ai/remote_qr_overlay.dart';
import 'router.dart';
import 'shell/idle_attract_host.dart';
import 'shell/virtual_keyboard.dart';

class KioskApp extends ConsumerWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Davlat Kadastrlari Palatasi — Kiosk',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      builder: (context, child) => HeartbeatHost(
        child: AmbientVoiceHost(
          child: IdleAttractHost(child: _Canvas(child: child ?? const SizedBox())),
        ),
      ),
    );
  }
}

/// Fixed 1080×1920 design canvas: uniform-scaled + letterboxed (web fit()).
class _Canvas extends StatelessWidget {
  const _Canvas({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: T.letterbox,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: Env.canvasW,
            height: Env.canvasH,
            // Material = light page background (T.bg) + provides DefaultTextStyle
            // (without it: dark letterbox shows through + yellow-underline text).
            child: Material(
              color: T.bg,
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  const RemoteQrOverlay(), // burchakдаги telefon-QR pult
                  const Positioned(left: 0, right: 0, bottom: 0, child: VkOverlay()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
