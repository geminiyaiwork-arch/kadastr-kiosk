import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/i18n/strings.dart';
import '../core/theme/icons.dart';
import '../core/theme/press.dart';
import '../core/theme/text_styles.dart';
import '../core/theme/tokens.dart';
import 'lang_modal.dart';
import 'operator_menu.dart';

/// 9 service tiles (id, icon, accent class) — from app.js SVC_LIST.
const svcList = [
  ('property', 'property', 'green'),
  ('xatlov', 'xatlov', 'green'),
  ('docs', 'document', 'blue'),
  ('appeal', 'appeal', 'green'),
  ('reception', 'reception', 'blue'),
  ('illegal', 'illegal', 'green'),
  ('districts', 'districts', 'green'),
  ('ai', 'ai', 'accent'),
  ('phones', 'phones', 'blue'),
];

/// Bottom-nav items (route, icon key, label key).
const _navItems = [
  ('/', 'navHome', 'navHome'),
  ('/services', 'navServices', 'navServices'),
  ('/news', 'navNews', 'navNews'),
  ('/social', 'navSocial', 'navSocial'),
];

/// Standard kiosk page chrome: header + scrollable body + bottom nav.
class KioskScaffold extends StatelessWidget {
  const KioskScaffold({super.key, required this.body, this.scroll = true});
  final Widget body;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final content = _FadeUp(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 36),
        child: body,
      ),
    );
    return Column(
      children: [
        const _Header(),
        Expanded(
          child: scroll ? SingleChildScrollView(child: content) : content,
        ),
        const _BottomNav(),
      ],
    );
  }
}

/// One-shot fade + slide-up on mount (web .kt-body fadeUp .4s).
class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 44),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: T.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _LogoTap(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const _Clock(),
              const SizedBox(height: 8),
              Press(
                onTap: () => showLangModal(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: T.line, width: 1.5),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: T.shadow,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    kIcon('globe', size: 26, color: T.navy, stroke: 1.8),
                    const SizedBox(width: 10),
                    Text(t['langName'], style: K.lang),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Logo tap: single tap → home; 10 rapid taps → hidden operator menu.
class _LogoTap extends StatefulWidget {
  const _LogoTap();
  @override
  State<_LogoTap> createState() => _LogoTapState();
}

class _LogoTapState extends State<_LogoTap> {
  int _taps = 0;
  DateTime _first = DateTime.fromMillisecondsSinceEpoch(0);
  void _tap() {
    final now = DateTime.now();
    if (now.difference(_first).inSeconds > 3) {
      _taps = 0;
      _first = now;
    }
    _taps++;
    if (_taps >= 10) {
      _taps = 0;
      showOperatorMenu(context);
      return;
    }
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: const _CrossfadeLogo(),
    );
  }
}

/// Header logo that cross-fades logo1 ↔ logo2 every ~9s (web logo show).
class _CrossfadeLogo extends StatefulWidget {
  const _CrossfadeLogo();
  @override
  State<_CrossfadeLogo> createState() => _CrossfadeLogoState();
}

class _CrossfadeLogoState extends State<_CrossfadeLogo> {
  Timer? _t;
  bool _first = true;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 9), (_) => setState(() => _first = !_first));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        // 3D Y-flip + fade (like the web logo show)
        final flip = Tween<double>(begin: math.pi / 2, end: 0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut));
        return AnimatedBuilder(
          animation: anim,
          child: child,
          builder: (_, c) => Opacity(
            opacity: anim.value,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(flip.value),
              child: c,
            ),
          ),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: SizedBox(
        key: ValueKey(_first),
        height: 104,
        child: Image.asset(
          _first ? 'assets/images/logo1.png' : 'assets/images/logo2.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  DateTime _now = DateTime.now();
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(DateFormat('HH:mm').format(_now), style: K.clock),
        Text(DateFormat('dd.MM.yyyy').format(_now), style: K.date),
      ],
    );
  }
}

class _BottomNav extends ConsumerWidget {
  const _BottomNav();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final loc = GoRouterState.of(context).matchedLocation;
    return Container(
      height: 128,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(gradient: T.gNavyH),
      child: Row(
        children: _navItems.map((it) {
          final active = loc == it.$1;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go(it.$1),
              child: Opacity(
                opacity: active ? 1 : 0.62,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    kIcon(it.$2, size: 42, color: Colors.white, stroke: 1.8),
                    const SizedBox(height: 9),
                    Text(t[it.$3], style: K.navLabel),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: active ? 46 : 0,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Sub-page header with a back button + title (web pgHead).
class PageHead extends StatelessWidget {
  const PageHead(this.title, {super.key, this.sub});
  final String title;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Press(
            scale: 0.92,
            onTap: () => context.go('/'),
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: T.line, width: 1.5),
                borderRadius: BorderRadius.circular(18),
                boxShadow: T.shadow,
              ),
              alignment: Alignment.center,
              child: const Text('‹', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: T.navy)),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: K.pgTitle),
                if (sub != null) ...[const SizedBox(height: 4), Text(sub!, style: K.pgSub)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
