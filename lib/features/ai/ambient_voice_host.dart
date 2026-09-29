import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../router.dart';
import 'voice_controller.dart';
import '../../core/services/wake_bridge.dart';

/// Yagona doimiy ovoz tinglovchisini ishga tushiradi va tilini sinxron tutadi.
///
/// 1.9.48: tinglash TEGINISHSIZ boshlanadi — birinchi kadrdan [autoStartDelay] keyin
/// (avval faqat birinchi teginishda boshlanardi → qayta ishga tushgan kioskda "Alomat"
/// hech kim ekranga tegmaguncha ishlamasdi). Teginish — zaxira trigger. Mikrofon tayyor
/// bo'lmasa VoiceController o'zi backoff bilan qayta urinadi (2s, 5s, 10s, har 30s).
/// Zastavkada tinglash "faqat chaqiruv so'zi" rejimida (wake-only).
class AmbientVoiceHost extends ConsumerStatefulWidget {
  const AmbientVoiceHost({super.key, required this.child, this.autoStartDelay = const Duration(seconds: 2)});
  final Widget child;

  /// null = avto-start yo'q (faqat teginish).
  final Duration? autoStartDelay;
  @override
  ConsumerState<AmbientVoiceHost> createState() => _AmbientVoiceHostState();
}

class _AmbientVoiceHostState extends ConsumerState<AmbientVoiceHost> {
  Timer? _auto;
  WakeBridge? _bridge; // 1.9.53: openWakeWord sidecar (Windows) — ~0.3 s uyg'onish

  @override
  void initState() {
    super.initState();
    final d = widget.autoStartDelay;
    if (d != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _auto = Timer(d, _ensureStarted);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _bridge?.stop();
    super.dispose();
  }

  void _ensureStarted() {
    if (!mounted) return;
    final notifier = ref.read(voiceProvider.notifier);
    if (notifier.isOn) return;
    notifier.startAmbient(
      lang: ref.read(localeProvider),
      onAiPage: () => ref.read(currentRouteProvider) == '/ai',
      // /appeal (kamera mikrofonni oladi), /face-enroll (ism yozadi) va intro-video paytida
      // tinglamaymiz. ZASTAVKA endi istisno EMAS — u wake-only rejim (pastda).
      canListen: () => ref.read(currentRouteProvider) != '/appeal' &&
          ref.read(currentRouteProvider) != '/face-enroll' &&
          !ref.read(introPlayingProvider),
      // Zastavkada faqat "Alomat" bilan boshlangan gap qabul qilinadi (video ovozi o'zini
      // uyg'otmasin — VoiceController.attractGuard).
      wakeOnly: () => ref.read(attractProvider),
      dismissAttract: () => ref.read(attractProvider.notifier).state = false,
      navToAi: () => ref.read(routerProvider).go('/ai'),
      navTo: (route) => ref.read(routerProvider).go(route),
    );
    if (_bridge == null && WakeBridge.sidecarPath() != null) {
      final b = WakeBridge();
      b.log = (m) => debugPrint('[wake-bridge] $m');
      b.onWake = (score) {
        if (!mounted) return;
        ref.read(voiceProvider.notifier).externalWake(score);
      };
      _bridge = b;
      b.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    // keep the recogniser language in sync with the UI language
    ref.listen(localeProvider, (_, lang) => ref.read(voiceProvider.notifier).setLang(lang));
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        ref.read(voiceProvider.notifier).noteTouch();
        _ensureStarted(); // zaxira: avto-start hali bo'lmagan/muvaffaqiyatsiz bo'lsa
      },
      child: widget.child,
    );
  }
}
