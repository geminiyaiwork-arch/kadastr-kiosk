import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_win/video_player_win.dart';

import '../core/env.dart';
import '../core/i18n/strings.dart';
import '../core/services/screensaver_cache.dart';
import '../core/theme/text_styles.dart';
import '../core/theme/tokens.dart';
import '../router.dart';
import '../features/ai/voice_controller.dart';

/// Idle handling: at 90s reset to home + uz; at 120s show the attract screen.
///
/// ZASTAVKA VIDEO = Windows Media Foundation (`video_player_win`), media_kit(libmpv) O'RNIGA.
/// Video `setLooping(true)` bilan UZLUKSIZ o'ynaydi (ishonchli); animatsion o'tish esa ALOHIDA
/// taymer bilan (10 xil 3D effekt playback ustidan) — playbackни BUZMAYDI.
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
    ref.listenManual(voiceActivityProvider, (_, __) => _idle = 0);
    // Bosh menyuga ('/') qaytilса — gapirayotган ovoz (sahifa-e'loni yoki AI javob) TO'XTASIN.
    ref.listenManual(currentRouteProvider, (_, next) {
      if (next == '/') { try { ref.read(voiceProvider.notifier).stopSpeaking(); } catch (_) {} }
    });
    Future.microtask(() => ref.read(screensaverCacheProvider.future));
  }

  void _setAttract(bool on) {
    setState(() => _attract = on);
    // ZASTAVKA chiqganда fonда AI ovozi gapirmasin — darhol to'xtatamiz.
    if (on) { try { ref.read(voiceProvider.notifier).stopSpeaking(); } catch (_) {} }
    Future.microtask(() {
      if (mounted) ref.read(attractProvider.notifier).state = on;
    });
  }

  void _tick() {
    // BAND (video ko'rish / video-murojaat) — idle'ни nolда ushlaymiz, asosiy menyuga OTMAYMIZ.
    if (ref.read(kioskBusyProvider) > 0) { _idle = 0; return; }
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

class _AttractScreenState extends ConsumerState<_AttractScreen> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat(reverse: true);
  late final AnimationController _fxA = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));

  List<String> _urls = const [];
  int _idx = 0;
  int _fxKind = 0;
  WinVideoPlayerController? _vc;
  bool _ready = false;
  bool _muted = false;
  bool _showFx = false;
  Timer? _fxTimer, _advTimer;
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _urls = await ref.refresh(screensaverCacheProvider.future).timeout(const Duration(seconds: 60));
    } catch (_) {
      _urls = const [];
    }
    if (!mounted || _urls.isEmpty) return;
    await _open(0);
    if (!mounted) return;
    // 3D "flourish" o'tishlar OLIB TASHLANDI (2026-07-28, user: "bachkana") — davlat
    // kioski uchun jiddiy: video silliq loop, videolar orasida faqat mayin crossfade.
    // Bir nechta video bo'lsa — har ~20s keyingisiga o'tadi (crossfade _advance ichida).
    if (_urls.length >= 2) {
      _advTimer = Timer.periodic(const Duration(seconds: 20), (_) => _advance());
    }
  }

  Future<void> _open(int i) async {
    _idx = i % _urls.length;
    final old = _vc;
    _vc = null;
    if (old != null) { try { await old.dispose(); } catch (_) {} }
    try {
      final c = WinVideoPlayerController.file(File(_urls[_idx]));
      await c.initialize();
      if (!mounted || !c.value.isInitialized) { try { await c.dispose(); } catch (_) {} return; }
      c.setLooping(true); // UZLUKSIZ — completion-detection'ga tayanmaymiz (ishonchli)
      await c.setVolume(_muted ? 0 : 1.0);
      await c.play();
      setState(() { _vc = c; _ready = true; });
    } catch (_) {}
  }

  Future<void> _playFx() async {
    if (!mounted || _showFx || _vc == null) return;
    _fxKind = _rnd.nextInt(10);
    setState(() => _showFx = true);
    try { await _fxA.forward(from: 0); } catch (_) {}
    if (mounted) setState(() => _showFx = false);
  }

  Future<void> _advance() async {
    if (!mounted || _urls.length < 2 || _showFx) return;
    await _open(_idx + 1);
    _playFx();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    try { _vc?.setVolume(_muted ? 0 : 1.0); } catch (_) {}
  }

  void _startMenu() {
    widget.onTouch();
    ref.read(routerProvider).go('/');
  }

  Widget _video(WinVideoPlayerController c) => FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: c.value.size.width <= 0 ? 1080 : c.value.size.width,
          height: c.value.size.height <= 0 ? 1920 : c.value.size.height,
          child: WinVideoPlayer(c),
        ),
      );

  @override
  void dispose() {
    _fxTimer?.cancel();
    _advTimer?.cancel();
    _c.dispose();
    _fxA.dispose();
    try { _vc?.dispose(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final cur = _vc;
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
            if (_ready && cur != null && cur.value.isInitialized)
              _showFx ? _TransitionFx(kind: _fxKind, anim: _fxA, child: _video(cur)) : _video(cur),
            if (!_ready)
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
            const Positioned(top: 44, right: 44, child: _ClockWidget()),
            // Chiroyli chaqiruv matni — "Yordam kerak bo'lsa «KAI» deb chaqiring"
            if (_ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 210,
                child: Center(child: _CallHint(text: t['attractCall'] ?? 'Yordam kerak bo‘lsa «KAI» deb chaqiring')),
              ),
            Positioned(
              left: 40,
              bottom: 48,
              child: _PillBtn(
                icon: Icons.touch_app_rounded,
                label: t['attractAppeal'] ?? 'Boshlash',
                onTap: _startMenu,
              ),
            ),
            if (_ready)
              Positioned(
                right: 40,
                bottom: 48,
                child: _PillBtn(
                  icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  label: (_muted ? t['attractUnmute'] : t['attractMute']) ?? 'Ovozni o‘chirish',
                  onTap: _toggleMute,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Zastavkadagi chiroyli chaqiruv matni — mikrofon ikonkasi + "«KAI» deb chaqiring",
/// yumshoq nafas oluvchi glow (jiddiy, davlat-kioski uslubi).
class _CallHint extends StatefulWidget {
  const _CallHint({required this.text});
  final String text;
  @override
  State<_CallHint> createState() => _CallHintState();
}

class _CallHintState extends State<_CallHint> with SingleTickerProviderStateMixin {
  late final AnimationController _p =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _p,
      builder: (_, __) {
        final glow = 0.35 + 0.35 * _p.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xE61B2A4A), Color(0xE60E1A34)]),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Color.fromRGBO(120, 150, 255, glow), width: 2),
            boxShadow: [
              BoxShadow(color: Color.fromRGBO(84, 87, 245, glow * 0.6), blurRadius: 40, spreadRadius: 2),
              const BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B4BF0), Color(0xFF4A3FDD)]),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(width: 22),
            Text(widget.text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    shadows: [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 2))])),
          ]),
        );
      },
    );
  }
}

/// Qorong'i yarim-shaffof pill-knopka.
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

/// Soat + sana (yuqori o'ng burchak).
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
                color: Colors.white, fontSize: 54, fontWeight: FontWeight.w800, height: 1.0,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2))])),
        const SizedBox(height: 4),
        Text(date,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 2))])),
      ],
    );
  }
}

/// 10 xil 3D animatsiya (video ustidan davriy qo'llanadi).
class _TransitionFx extends StatelessWidget {
  const _TransitionFx({required this.kind, required this.anim, required this.child});
  final int kind;
  final Animation<double> anim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, ch) {
        final v = Curves.easeInOutCubic.transform(anim.value);
        switch (kind) {
          case 1:
            return Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()..setEntry(3, 2, 0.0011)..rotateY((1 - v) * 0.7),
              child: FractionalTranslation(translation: Offset(1 - v, 0), child: ch),
            );
          case 2:
            return Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()..setEntry(3, 2, 0.0011)..rotateX((1 - v) * -0.7),
              child: FractionalTranslation(translation: Offset(0, 1 - v), child: ch),
            );
          case 3:
            return Opacity(opacity: v, child: Transform.scale(scale: 0.72 + 0.28 * v, child: ch));
          case 4:
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..setEntry(3, 2, 0.0012)..rotateY((1 - v) * math.pi / 2),
              child: ch,
            );
          case 5:
            return Opacity(
              opacity: v,
              child: Transform.rotate(angle: (1 - v) * 0.9, child: Transform.scale(scale: 0.6 + 0.4 * v, child: ch)),
            );
          case 6:
            return ClipPath(clipper: _CircleRevealClipper(v), child: ch);
          case 7:
            return ClipPath(clipper: _BlindsClipper(v), child: ch);
          case 8:
            return ClipPath(clipper: _CheckerClipper(v), child: ch);
          case 9:
            return ClipPath(clipper: _LeafScatterClipper(v), child: ch);
          default:
            return Opacity(opacity: v, child: ch);
        }
      },
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  _CircleRevealClipper(this.v);
  final double v;
  @override
  Path getClip(Size s) {
    final r = v * math.sqrt(s.width * s.width + s.height * s.height) / 2;
    return Path()..addOval(Rect.fromCircle(center: Offset(s.width / 2, s.height / 2), radius: r));
  }

  @override
  bool shouldReclip(_CircleRevealClipper old) => old.v != v;
}

class _BlindsClipper extends CustomClipper<Path> {
  _BlindsClipper(this.v);
  final double v;
  static const n = 9;
  @override
  Path getClip(Size s) {
    final p = Path();
    final w = s.width / n;
    for (var i = 0; i < n; i++) {
      final local = ((v * 1.4) - i * 0.045).clamp(0.0, 1.0);
      p.addRect(Rect.fromLTWH(i * w, 0, w * local, s.height));
    }
    return p;
  }

  @override
  bool shouldReclip(_BlindsClipper old) => old.v != v;
}

class _CheckerClipper extends CustomClipper<Path> {
  _CheckerClipper(this.v);
  final double v;
  static const cols = 6, rows = 10;
  @override
  Path getClip(Size s) {
    final p = Path();
    final w = s.width / cols, h = s.height / rows;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final delay = ((r + c) % 6) * 0.08;
        final local = ((v * 1.6) - delay).clamp(0.0, 1.0);
        if (local <= 0) continue;
        final cw = w * local, chh = h * local;
        p.addRect(Rect.fromLTWH(c * w + (w - cw) / 2, r * h + (h - chh) / 2, cw, chh));
      }
    }
    return p;
  }

  @override
  bool shouldReclip(_CheckerClipper old) => old.v != v;
}

class _LeafScatterClipper extends CustomClipper<Path> {
  _LeafScatterClipper(this.v);
  final double v;
  static final _pts = List.generate(26, (i) {
    final rnd = math.Random(i * 97 + 13);
    return Offset(rnd.nextDouble(), rnd.nextDouble());
  });
  @override
  Path getClip(Size s) {
    final p = Path();
    final maxR = math.max(s.width, s.height) * 0.34;
    for (var i = 0; i < _pts.length; i++) {
      final delay = (i % 8) * 0.06;
      final local = ((v * 1.5) - delay).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final dx = (1 - local) * 60 * ((i % 2 == 0) ? 1 : -1);
      p.addOval(Rect.fromCircle(
        center: Offset(_pts[i].dx * s.width + dx, _pts[i].dy * s.height),
        radius: maxR * local,
      ));
    }
    return p;
  }

  @override
  bool shouldReclip(_LeafScatterClipper old) => old.v != v;
}
