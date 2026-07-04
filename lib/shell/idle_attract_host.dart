import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/env.dart';
import '../core/i18n/strings.dart';
import '../core/network/api_client.dart';
import '../core/network/repository.dart';
import '../core/services/avatar_player.dart';
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
    // Ovozli suhbat ham "faollik" — suhbat o'rtasida zastavka ochilib ketmasin
    ref.listenManual(voiceActivityProvider, (_, __) => _idle = 0);
  }

  void _setAttract(bool on) {
    setState(() => _attract = on);
    // mikrofon-gate uchun global bayroq (zastavka ochiq payt tinglanmaydi)
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

class _AttractScreenState extends ConsumerState<_AttractScreen> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat(reverse: true);

  // ZASTAVKA VIDEOLARI (admin yuklagan) — video-xavfsiz platformada to'liq ekran.
  // Bir videodan ikkinchisiga 10 xil TASODIFIY animatsiya bilan o'tadi.
  List<String> _urls = const [];
  Player? _cur, _next;
  VideoController? _curC, _nextC;
  int _idx = 0;
  int _fxKind = 0;
  bool _videoReady = false;
  bool _transing = false;
  bool _muted = false;        // zastavka video ovozi (foydalanuvchi o'chira oladi)
  bool _showCurFx = false;    // yakka video: har aylanishда joriy videoга animatsiya
  StreamSubscription<bool>? _doneSub;
  final _rnd = math.Random();
  late final AnimationController _fxA = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    _tryVideo();
  }

  // Zastavka diagnostikasi — qurilmada nima bo'lganini serverда ko'ramiz ([zastavka] ...).
  void _log(String msg) {
    try {
      ref.read(dioProvider).post('/ai/heard',
          data: {'text': '[zastavka] $msg', 'device': ''}).then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  Process? _mpv;

  /// LINUX: video-zastavka Flutter ICHIDA emas — MUSTAQIL mpv-oynada (to'liq ekran).
  /// Sabab: bu mashinalarda Mesa-gallium Flutter GL-teksturasida segfault beradi
  /// (26.0.8 ham, 26.1.2 ham — coredump'lar bilan tasdiqlangan). Tashqi mpv oynasi
  /// o'z renderida ishlaydi — ilova umuman xavf ostida emas. Ekranga tegilsa yopiladi.
  Future<void> _startMpvLinux() async {
    final conf = File('${Directory.systemTemp.path}/kai_mpv_input.conf');
    await conf.writeAsString('MBTN_LEFT quit\nMOUSE_BTN0 quit\nENTER quit\nESC quit\n');
    final args = <String>[
      '--fs', '--no-osc', '--really-quiet', '--loop-playlist=inf',
      '--no-input-default-bindings', '--input-conf=${conf.path}', ..._urls,
    ];
    _mpv = await Process.start('mpv', args);
    _mpv!.exitCode.then((_) {
      _mpv = null;
      if (mounted) widget.onTouch(); // videoga tegildi -> zastavka ham yopiladi
    });
  }

  Future<void> _tryVideo() async {
    try {
      if (!AvatarPlayer.supported) {
        if (!Platform.isLinux) return;
        // Linux: ro'yxatni olib, tashqi mpv bilan ko'rsatamiz
        _urls = await ref.refresh(screensaverProvider.future).timeout(const Duration(seconds: 6));
        if (_urls.isEmpty || !mounted) return;
        await _startMpvLinux();
        return;
      }
    } catch (_) {
      return; // mpv yo'q/xato — gradient-logo qoladi
    }
    try {
      // refresh: birinchi urinishda tarmoq bo'lmasa bo'sh ro'yxat KESHLANIB
      // qolmasin; admin yangi video qo'shsa restart'siz yetib kelsin
      _urls = await ref.refresh(screensaverProvider.future).timeout(const Duration(seconds: 8));
      if (_urls.isEmpty || !mounted) { _log('video ro\'yxati bo\'sh'); return; }
      final p = Player();
      _cur = p;
      _curC = VideoController(p);
      await p.setVolume(_muted ? 0 : 100);
      // PlaylistMode.loop O'RNATILMAYDI — loopни o'zimiz boshqaramiz (har aylanishда animatsiya).
      _watchEnd(p);
      await p.open(Media(_urls[0]), play: true);
      if (!mounted) {
        try { await p.dispose(); } catch (_) {}
        return;
      }
      setState(() => _videoReady = true);
      _log('video ochildi (${_urls.length} ta)');
    } catch (e) {
      // video bo'lmadi — oddiy zastavka qoladi
      _log('xato: $e');
    }
  }

  void _watchEnd(Player p) {
    _doneSub?.cancel();
    _doneSub = p.stream.completed.listen((done) async {
      if (!done) return;
      if (_urls.length >= 2) {
        _advance();               // ko'p video: keyingisiga animatsiya bilan o'tadi
      } else {
        _loopSingleWithFx();      // yakka video: boshidan + TASODIFIY animatsiya
      }
    });
  }

  /// Yakka video: tugagach boshidan o'ynaydi va joriy videoга 10 uslubdan
  /// tasodifiy animatsiya qo'llanadi (foydalanuvchi animatsiyalarni ko'radi).
  Future<void> _loopSingleWithFx() async {
    if (_transing || !mounted || _cur == null) return;
    _transing = true;
    try {
      _fxKind = _rnd.nextInt(10);
      try {
        await _cur!.seek(Duration.zero);
        await _cur!.play();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _showCurFx = true);
      await _fxA.forward(from: 0);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _showCurFx = false);
      _transing = false;
    }
  }

  /// Keyingi videoga TASODIFIY animatsiya bilan o'tish.
  Future<void> _advance() async {
    if (_transing || !mounted || _urls.length < 2) return;
    _transing = true;
    Player? p;
    try {
      _idx = (_idx + 1) % _urls.length;
      p = Player();
      final c = VideoController(p);
      // DARHOL state'ga yozamiz — await o'rtasida dispose bo'lsa ham
      // dispose() bu playerni ko'rib yopadi (ovoz-leak bo'lmasin)
      _next = p;
      _nextC = c;
      await p.setVolume(_muted ? 0 : 100);
      await p.open(Media(_urls[_idx]), play: true);
      _watchEnd(p); // EOF darhol kuzatiladi (qisqa klip transition ichida tugasa ham)
      if (!mounted) return; // dispose() _next'ni yopadi
      try {
        await _cur?.setVolume(0);
      } catch (_) {} // eski ovoz o'chadi (ikki ovoz aralashmasin)
      // birinchi kadr tayyor bo'lishini qisqa kutamiz (bo'sh/qora kirish bo'lmasin)
      try {
        await p.stream.width.first.timeout(const Duration(seconds: 4));
      } catch (_) {}
      if (!mounted) return;
      _fxKind = _rnd.nextInt(10);
      setState(() {});
      await _fxA.forward(from: 0);
      if (!mounted) return;
      final old = _cur;
      _cur = _next;
      _curC = _nextC;
      _next = null;
      _nextC = null;
      setState(() {});
      try {
        await old?.dispose();
      } catch (_) {}
    } catch (_) {
    } finally {
      _transing = false;
      // transition davomida EOF o'tkazib yuborilgan bo'lsa — davom etamiz
      if (mounted && (_cur?.state.completed ?? false)) {
        scheduleMicrotask(_advance);
      }
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    final v = _muted ? 0.0 : 100.0;
    try { _cur?.setVolume(v); } catch (_) {}
    try { _next?.setVolume(v); } catch (_) {}
  }

  void _startAppeal() {
    // zastavkani yopamiz va to'g'ridan-to'g'ri Murojaat sahifasini ochamiz
    widget.onTouch();
    ref.read(routerProvider).go('/appeal');
  }

  @override
  void dispose() {
    try { _mpv?.kill(); } catch (_) {}
    _c.dispose();
    _fxA.dispose();
    _doneSub?.cancel();
    try {
      _cur?.dispose();
    } catch (_) {}
    try {
      _next?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    return GestureDetector(
      onTap: widget.onTouch,
      child: Container(
        decoration: const BoxDecoration(
          gradient:
              LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [T.navy2, T.letterbox]),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // JORIY video — yakka-video aylanishда unга ham tasodifiy animatsiya qo'llanadi
            if (_videoReady && _curC != null)
              _showCurFx
                  ? _TransitionFx(
                      kind: _fxKind,
                      anim: _fxA,
                      child: Video(controller: _curC!, controls: NoVideoControls, fit: BoxFit.contain))
                  : Video(controller: _curC!, controls: NoVideoControls, fit: BoxFit.contain),
            // KIRUVCHI video (ko'p video) — 10 xil animatsiyadan tasodifiysi bilan
            if (_nextC != null)
              _TransitionFx(
                kind: _fxKind,
                anim: _fxA,
                child: Video(controller: _nextC!, controls: NoVideoControls, fit: BoxFit.contain),
              ),
            if (!_videoReady)
              Column(
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
            // OVOZ o'chirish/yoqish knopkasi (faqat video bor bo'lsa) — yuqori o'ng burchakда
            if (_videoReady)
              Positioned(
                top: 40,
                right: 40,
                child: _RoundBtn(
                  icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  onTap: _toggleMute,
                ),
              ),
            // Pastдa: "Murojaatni boshla" knopkasi + "Ekranga teging" ishorasi
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Katta, ko'zga tashlanadigan "Murojaatni boshla" knopkasi
                  Center(
                    child: GestureDetector(
                      onTap: _startAppeal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [T.green, Color(0xFF16A34A)]),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.record_voice_over_rounded, color: Colors.white, size: 34),
                            const SizedBox(width: 14),
                            Text(t['attractAppeal'] ?? 'Murojaatni boshla',
                                style: K.heroSub.copyWith(fontSize: 30, color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
                      decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(30)),
                      child: Text(t['attractSub'] ?? '', style: K.heroSub.copyWith(fontSize: 22, color: Colors.white)),
                    ),
                  ),
                ],
              ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dumaloq yarim-shaffof knopka (ovoz o'chirish/yoqish uchun).
class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: const BoxDecoration(
          color: Color(0x80000000),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: 40),
      ),
    );
  }
}

/// 10 xil video-o'tish animatsiyasi (kiruvchi videoga qo'llanadi):
/// 0 xira-o'tish, 1 o'ngdan 3D siljish, 2 pastdan 3D siljish, 3 kattalashib kirish,
/// 4 eshikday 3D burilish, 5 aylanib-kirish, 6 doira ochilish, 7 jalyuzi,
/// 8 shaxmat-kublar, 9 shamol-barglar (uchma bo'laklar).
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
          case 1: // o'ngdan 3D siljish (perspektiva bilan uchib kiradi)
            return Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0011)
                ..rotateY((1 - v) * 0.7),
              child: FractionalTranslation(translation: Offset(1 - v, 0), child: ch),
            );
          case 2: // pastdan 3D siljish (perspektiva bilan yotib turib ko'tariladi)
            return Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0011)
                ..rotateX((1 - v) * -0.7),
              child: FractionalTranslation(translation: Offset(0, 1 - v), child: ch),
            );
          case 3: // kattalashib kirish
            return Opacity(opacity: v, child: Transform.scale(scale: 0.72 + 0.28 * v, child: ch));
          case 4: // eshikday 3D burilish
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY((1 - v) * math.pi / 2),
              child: ch,
            );
          case 5: // aylanib-kirish
            return Opacity(
              opacity: v,
              child: Transform.rotate(
                angle: (1 - v) * 0.9,
                child: Transform.scale(scale: 0.6 + 0.4 * v, child: ch),
              ),
            );
          case 6: // doira ochilish
            return ClipPath(clipper: _CircleRevealClipper(v), child: ch);
          case 7: // jalyuzi (vertikal panellar)
            return ClipPath(clipper: _BlindsClipper(v), child: ch);
          case 8: // shaxmat-kublar
            return ClipPath(clipper: _CheckerClipper(v), child: ch);
          case 9: // shamol-barglar: burchakdan uchib kirib yig'iladigan bo'laklar
            return ClipPath(clipper: _LeafScatterClipper(v), child: ch);
          default: // 0: xira-o'tish
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
      // har panel ozgina kechikib ochiladi
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

/// "Shamol-barg": tasodifiy joylashgan dumaloq "barg" dog'lari kattalashib,
/// shamolda suzib kelganday butun ekranni qoplaydi.
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
      // barg shamolda chapdan o'ngga ozgina suzadi
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
