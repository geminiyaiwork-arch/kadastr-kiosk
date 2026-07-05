import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../core/i18n/strings.dart';
import '../core/theme/text_styles.dart';
import '../core/theme/tokens.dart';
import '../router.dart';

/// Idle handling: at 90s reset to home + uz; at 120s show the attract screen.
/// Any pointer wakes it.
///
/// VIDEO ZASTAVKA OLIB TASHLANGAN (media_kit/libmpv DLL'ni Smart App Control bloklaydi).
/// Zastavka endi animatsiyali LOGO + soat + "Boshlash" tugmasi (statik, xavfsiz).
class IdleAttractHost extends ConsumerStatefulWidget {
  const IdleAttractHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<IdleAttractHost> createState() => _IdleAttractHostState();
}

class _IdleAttractHostState extends ConsumerState<IdleAttractHost> {
  int _idle = 0;
  bool _attract = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Ovozli suhbat ham "faollik" — suhbat o'rtasida zastavka ochilib ketmasin
    ref.listenManual(voiceActivityProvider, (_, __) => _idle = 0);
  }

  void _setAttract(bool on) {
    setState(() => _attract = on);
    Future.microtask(() {
      if (mounted) ref.read(attractProvider.notifier).state = on;
    });
  }

  void _tick() {
    _idle++;
    if (_idle == Env.resetSec && !_attract) {
      final loc = ref.read(currentRouteProvider);
      if (loc != '/' || ref.read(localeProvider) != 'uz') {
        ref.read(localeProvider.notifier).state = 'uz';
        ref.read(routerProvider).go('/');
      }
    }
    if (_idle >= Env.attractSec && !_attract) _setAttract(true);
  }

  void _wake() {
    _idle = 0;
    if (_attract) _setAttract(false);
  }

  void _resetIdle() => _idle = 0;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdle(),
      child: Stack(
        children: [
          widget.child,
          if (_attract)
            Positioned.fill(
              child: ColoredBox(
                color: T.letterbox,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: Env.canvasW,
                      height: Env.canvasH,
                      child: Material(
                        color: T.navy2,
                        child: _AttractScreen(onTouch: _wake),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttractScreen extends ConsumerStatefulWidget {
  const _AttractScreen({required this.onTouch});
  final VoidCallback onTouch;
  @override
  ConsumerState<_AttractScreen> createState() => _AttractScreenState();
}

class _AttractScreenState extends ConsumerState<_AttractScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _startMenu() {
    widget.onTouch();
    ref.read(routerProvider).go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    return GestureDetector(
      onTap: widget.onTouch,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [T.navy2, T.letterbox]),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Markazда — nafas oluvchi (yuqori-past) LOGO + "Ekranga teging"
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) => Transform.translate(offset: Offset(0, -18 + 36 * _c.value), child: child),
                  child: Image.asset('assets/images/logo.png', width: 300, fit: BoxFit.contain),
                ),
                const SizedBox(height: 44),
                Text(t['attractSub'] ?? '', style: K.heroSub.copyWith(fontSize: 32)),
              ],
            ),
            // Soat + sana — yuqori o'ng
            const Positioned(top: 44, right: 44, child: _ClockWidget()),
            // Pastki-CHAP: "Boshlash"
            Positioned(
              left: 40,
              bottom: 48,
              child: _PillBtn(
                icon: Icons.touch_app_rounded,
                label: t['attractAppeal'] ?? 'Boshlash',
                onTap: _startMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Qorong'i yarim-shaffof pill-knopka (ikonка + matn).
class _PillBtn extends StatelessWidget {
  const _PillBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xB3121826),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x33FFFFFF), width: 1),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 20, offset: Offset(0, 6))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Soat + sana (yuqori o'ng burchak) — har soniyada yangilanadi.
class _ClockWidget extends StatefulWidget {
  const _ClockWidget();
  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  DateTime _now = DateTime.now();
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _2(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final time = '${_2(_now.hour)}:${_2(_now.minute)}';
    final date = '${_2(_now.day)}.${_2(_now.month)}.${_now.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 54,
                fontWeight: FontWeight.w800,
                height: 1.0,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2))])),
        const SizedBox(height: 4),
        Text(date,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 2))])),
      ],
    );
  }
}
