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
    if (_idle >= Env.attractSec && !_attract) setState(() => _attract = true);
  }

  void _wake() {
    _idle = 0;
    if (_attract) setState(() => _attract = false);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      child: Stack(
        children: [
          widget.child,
          if (_attract) _AttractScreen(onTouch: _wake),
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    return GestureDetector(
      onTap: widget.onTouch,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [T.navy2, T.letterbox]),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, child) => Transform.translate(offset: Offset(0, -18 + 36 * _c.value), child: child),
              child: Image.asset('assets/images/logo.png', width: 280, fit: BoxFit.contain),
            ),
            const SizedBox(height: 40),
            Text(t['attractSub'] ?? '', style: K.heroSub.copyWith(fontSize: 30)),
          ],
        ),
      ),
    );
  }
}
