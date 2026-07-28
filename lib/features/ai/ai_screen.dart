import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player_win/video_player_win.dart';

import '../../core/env.dart';
import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/repository.dart';
import '../../core/services/avatar_player.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/fmt.dart';
import 'voice_controller.dart';

/// AI sahifa — IKKI HOLAT (user spec 2026-07-28):
///  1) KIRGANDA / persona-suhbatda: qora fon, TO'LIQ EKRAN avatar, salomlashuv
///     Wav2Lip lab-sinx VIDEO bilan (HTML-mockup bu bosqichda YO'Q).
///  2) MA'LUMOTLI JAVOB berganda: HTML-mockup 1:1 (kadastr-kiosk.html, 940x1832
///     dizayn-kanvas, FittedBox bilan masshtab): teskari-radiusli oq panel (ichida
///     JAVOB MATNI, raqamlar indigo-bold), dumaloq avatar (oq halqa + pulsli yashil
///     nuqta), qidiruv, "Kadastr xizmatlari" qatorlari (javob JADVALI shu uslubda,
///     jadvalsiz — 5 real xizmat qator), halo-mikrofon (gradient), to'lqinli status
///     pilli, '...' (suhbatni tozalash), pastda dekorativ chiziqlar.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});
  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

// ===== HTML dizayn konstantalari (kadastr-kiosk.html :root) =====
const _dW = 940.0, _dH = 1832.0; // dizayn kanvas
const _cBg = Color(0xFFEEF1FB);
const _cInk = Color(0xFF111C3F);
const _cInk2 = Color(0xFF1F2A4D);
const _cMuted = Color(0xFF9AA3BD);
const _cIndigo = Color(0xFF4F46E5);

class _Pal {
  const _Pal(this.icon, this.iconBg, this.pillBg, this.fg);
  final IconData icon;
  final Color iconBg, pillBg, fg;
}

const _palBlue = _Pal(Icons.description_rounded, Color(0xFFE3EBFD), Color(0xFFE8EFFD), Color(0xFF2F6BED));
const _palGreen = _Pal(Icons.location_on_rounded, Color(0xFFD5F4E6), Color(0xFFDEF6EC), Color(0xFF12B981));
const _palPurple = _Pal(Icons.home_rounded, Color(0xFFEFE4FD), Color(0xFFF2E9FD), Color(0xFF8B5CF6));
const _palSky = _Pal(Icons.apartment_rounded, Color(0xFFDBEAFE), Color(0xFFE4EEFD), Color(0xFF3B82F6));
const _palOrange = _Pal(Icons.location_on_rounded, Color(0xFFFFE6D2), Color(0xFFFFECE0), Color(0xFFF97316));
const _pals = [_palBlue, _palGreen, _palPurple, _palSky, _palOrange];

class _AiScreenState extends ConsumerState<AiScreen> {
  // Burchakka chiqish spin'i FAQAT OLDINGA aylansin: har chiqishda +1 tur.
  bool _wasCorner = false;
  int _spins = 0;

  // AI "yuklanmoqda" (foizli warmup) holati
  Map<String, dynamic>? _warmup;
  Timer? _warmupPoll;
  bool get _isWarmup => _warmup != null && _warmup!['loading'] == true;

  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    Map<String, dynamic> w = const {'loading': false};
    try { w = await ref.read(aiWarmupProvider.future); } catch (_) {}
    if (!mounted) return;
    final loading = w['loading'] == true;
    ref.read(aiWarmupLoadingProvider.notifier).state = loading;
    setState(() => _warmup = w);
    final t = I18N[ref.read(localeProvider)]!;
    final vc = ref.read(voiceProvider.notifier);
    vc.resetConversation(); // eski javob/jadval tozalanadi
    // KIRISH (INTRO) VIDEOSI: admin joriy tilга yuklagan bo'lsa — o'sha video o'ynaydi
    // (AI GAPIRMAYDI, generatsiya QILMAYDI). Video tugagach mikrofon savolni eshitadi.
    // Yo'q bo'lsa — hozirgi salomlashuv (Wav2Lip greet).
    final playedIntro = await _maybePlayIntro();
    if (!mounted) return;
    if (!playedIntro) vc.greet(t['aiGreet']);
    if (loading) {
      _warmupPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshWarmup());
    }
  }

  WinVideoPlayerController? _introCtl;

  /// Admin yuklagan kirish videosini (joriy til) o'ynatadi. true = o'ynadi.
  Future<bool> _maybePlayIntro() async {
    if (!Platform.isWindows) return false;
    final lang = ref.read(localeProvider);
    int ts = 0;
    try {
      final r = await ref.read(dioProvider).get('/intro');
      final m = Map<String, dynamic>.from(r.data as Map);
      final rec = m[lang];
      if (rec is! Map || rec['has'] != true) return false;
      ts = (rec['ts'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return false;
    }
    try {
      // yuklab olib keshlaymiz (takror kirishда qayta yuklamaydi)
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}intro');
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}intro_${lang}_$ts.mp4');
      if (!await f.exists() || (await f.length()) < 1000) {
        final resp = await ref.read(dioProvider).get<List<int>>(
          '/intro',
          queryParameters: {'lang': lang},
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
        );
        final bytes = resp.data ?? const <int>[];
        if (bytes.length < 1000) return false;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        try { await tmp.rename(f.path); } catch (_) {}
      }
      final playFile = await f.exists() ? f : File('${f.path}.tmp');
      final c = WinVideoPlayerController.file(playFile);
      await c.initialize().timeout(const Duration(seconds: 8));
      if (!c.value.isInitialized || !mounted) { try { await c.dispose(); } catch (_) {} return false; }
      // AI ovozi/gapi bo'lmasin — intro paytida mikrofon TINGLAMAYDI (introPlaying)
      try { await ref.read(voiceProvider.notifier).stopSpeaking(); } catch (_) {}
      ref.read(introPlayingProvider.notifier).state = true;
      ref.read(kioskBusyProvider.notifier).state++; // idle-reset urmasin
      await c.setVolume(1.0);
      setState(() => _introCtl = c);
      await c.play();
      // tugashini kutamiz
      final done = Completer<void>();
      void listener() {
        final v = c.value;
        if (!v.isInitialized) return;
        final d = v.duration;
        final ended = (d.inMilliseconds > 0 && v.position >= d - const Duration(milliseconds: 160)) ||
            (!v.isPlaying && v.position > const Duration(milliseconds: 400) && v.position >= d - const Duration(milliseconds: 400));
        if (ended && !done.isCompleted) done.complete();
      }
      c.addListener(listener);
      final capMs = c.value.duration.inMilliseconds > 0 ? c.value.duration.inMilliseconds + 1500 : 60000;
      await Future.any<void>([done.future, Future<void>.delayed(Duration(milliseconds: capMs.clamp(3000, 120000)))]);
      c.removeListener(listener);
      return true;
    } catch (_) {
      return false;
    } finally {
      final c = _introCtl;
      if (mounted) setState(() => _introCtl = null);
      try { await c?.dispose(); } catch (_) {}
      try { ref.read(introPlayingProvider.notifier).state = false; } catch (_) {}
      try { ref.read(kioskBusyProvider.notifier).state--; } catch (_) {}
    }
  }

  Future<void> _refreshWarmup() async {
    Map<String, dynamic> w;
    try { w = Map<String, dynamic>.from((await ref.read(dioProvider).get('/ai/warmup')).data as Map); } catch (_) { return; }
    if (!mounted) return;
    final loading = w['loading'] == true;
    ref.read(aiWarmupLoadingProvider.notifier).state = loading;
    setState(() => _warmup = w);
    if (!loading) { _warmupPoll?.cancel(); }
  }

  double get _warmupProgress => ((_warmup?['progress'] as num?)?.toDouble() ?? 0).clamp(0, 100).toDouble();

  @override
  void dispose() {
    _warmupPoll?.cancel();
    ref.read(aiWarmupLoadingProvider.notifier).state = false;
    try { _introCtl?.dispose(); } catch (_) {}
    try { ref.read(introPlayingProvider.notifier).state = false; } catch (_) {}
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _q = '';
    _searchCtrl.clear();
  }

  /// Yozib yuborilgan (qidiruv) yoki xizmat qatoridан kelgan savol.
  void _ask(String q) {
    final s = q.trim();
    if (s.length < 2) return;
    final vc = ref.read(voiceProvider.notifier);
    vc.stopSpeaking();
    setState(_clearSearch);
    vc.askAI(s);
  }

  /// ESKI (qora ekran) status matni — emoji bilan.
  String _statusOld(VoiceUiState v, Map<String, dynamic> t) {
    final lang = ref.read(localeProvider);
    if (v.error == 'mic') return '🎤 ${t['aiMic']}';
    if (v.recording) {
      return {
        'uz': '🔴 Gapiring… (to‘xtatish uchun bosing)',
        'ru': '🔴 Говорите… (нажмите, чтобы остановить)',
        'en': '🔴 Speak… (tap to stop)',
      }[lang]!;
    }
    switch (v.phase) {
      case VoicePhase.thinking:
        return '⏳ ${t['aiThink']}';
      case VoicePhase.speaking:
        return '🔊 ${t['aiSpeaking']}';
      case VoicePhase.transcribing:
        return '…';
      case VoicePhase.listening:
        return v.heard.isEmpty ? '🎤 ${t['aiListening']}' : '🎤 «${v.heard}»';
      case VoicePhase.off:
        return '🎤 ${t['aiTapTalk']}';
    }
  }

  /// MOCKUP (och ekran) status matni — emojisiz (yonida animatsion to'lqin bor).
  String _statusNew(VoiceUiState v, Map<String, dynamic> t) {
    final lang = ref.read(localeProvider);
    if (v.error == 'mic') return t['aiMic'];
    if (v.recording) {
      return {
        'uz': 'Gapiring… (to‘xtatish uchun bosing)',
        'ru': 'Говорите… (нажмите, чтобы остановить)',
        'en': 'Speak… (tap to stop)',
      }[lang]!;
    }
    switch (v.phase) {
      case VoicePhase.thinking:
        return t['aiThink'];
      case VoicePhase.speaking:
        return t['aiSpeaking'];
      case VoicePhase.transcribing:
        return '…';
      case VoicePhase.listening:
        return v.heard.isEmpty ? t['aiListening'] : '«${v.heard}»';
      case VoicePhase.off:
        return t['aiTapTalk'];
    }
  }

  static const _fx = Duration(milliseconds: 520);
  static const _fxCurve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final v = ref.watch(voiceProvider);
    final avatar = ref.watch(avatarProvider).valueOrNull;
    final enabled = avatar?.enabled ?? false;
    final url = enabled ? '${Env.apiBase}/avatar/file?${avatar!.imageQuery}' : null;
    // JIM-HOLAT imo-ishora videosi tayyorlansin (Windows; bir marta yuklanadi)
    if (enabled) ref.read(avatarPlayerProvider.notifier).ensureIdle(avatar);
    // suggest = chala/tushunarsiz gap → xizmat kartalari bilan mockup ekranга o'tamiz
    // (avatar burchakka, javob paneliда "tanlang", pastда 5 xizmat qatori — bosiladi).
    final hasData = v.answer.isNotEmpty || v.suggest;

    // Yangi javob kelsa qidiruv tozalanadi (eski filtr yopishib qolmasin)
    ref.listen(voiceProvider.select((s) => s.answer), (prev, next) {
      if (prev != next && mounted) setState(_clearSearch);
    });

    return AnimatedContainer(
      duration: _fx,
      color: hasData ? _cBg : T.aiDark, // javobda OCH fon (HTML), aks holda qora avatar-ekran
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        // HTML dizayn-kanvas masshtabi (scale wrapper bilan bir xil):
        final s = math.min(w / _dW, h / _dH);
        final ox = (w - _dW * s) / 2, oy = (h - _dH * s) / 2;
        // Avatar: HTML .avatar {right:41; top:104; 212x212} — halqa 9px oq padding.
        final avRect = hasData
            ? Rect.fromLTWH(ox + (_dW - 41 - 212) * s, oy + 104 * s, 212 * s, 212 * s)
            : Rect.fromLTWH(0, 0, w, h);
        final ap = ref.watch(avatarPlayerProvider);
        final cornerNow = hasData;
        if (cornerNow && !_wasCorner) _spins++; // burchakka chiqishda bir tur oldinga
        _wasCorner = cornerNow;
        return Stack(
          children: [
            // ======= MOCKUP sahna (faqat MA'LUMOTLI JAVOBDA ko'rinadi) =======
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !hasData,
                child: AnimatedOpacity(
                  duration: _fx,
                  curve: _fxCurve,
                  opacity: hasData ? 1 : 0,
                  child: !hasData
                      ? const SizedBox.shrink()
                      : Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _dW,
                              height: _dH,
                              child: _MockStage(
                                t: t,
                                v: v,
                                statusText: _statusNew(v, t),
                                searchCtrl: _searchCtrl,
                                q: _q,
                                onQ: (s2) => setState(() => _q = s2),
                                onClearQ: () => setState(_clearSearch),
                                onAsk: _ask,
                                onBack: () => context.go('/'),
                                onMic: () => ref.read(voiceProvider.notifier).toggleTalk(),
                                onDots: () {
                                  final vc = ref.read(voiceProvider.notifier);
                                  vc.stopSpeaking();
                                  vc.resetConversation();
                                  setState(_clearSearch);
                                },
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),

            // ======= AVATAR (bitta widget: to'liq ekran <-> HTML doira ANIMATSIYA) =======
            AnimatedPositioned(
              duration: _fx,
              curve: _fxCurve,
              left: avRect.left,
              top: avRect.top,
              width: avRect.width,
              height: avRect.height,
              child: AnimatedRotation(
                turns: _spins.toDouble(),
                duration: _fx,
                curve: _fxCurve,
                child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                  AnimatedContainer(
                    duration: _fx,
                    curve: _fxCurve,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(hasData ? avRect.width / 2 : 0),
                      // HTML .ring: oq halqa (padding 9) + yumshoq soya
                      border: hasData ? Border.all(color: Colors.white, width: 9) : null,
                      boxShadow: hasData
                          ? [
                              if (v.speaking)
                                const BoxShadow(color: Color(0x59635BEB), blurRadius: 34, spreadRadius: 4)
                              else
                                const BoxShadow(color: Color(0x1A3C5096), blurRadius: 30, offset: Offset(0, 10)),
                            ]
                          : null,
                    ),
                    child: Builder(builder: (context) {
                      // GAPIRGANDA: LAB-SINXRON video (Wav2Lip). JIMда: ko'z-pirpirash idle-video
                      // (server rasmdan avto-yasagan) loop; u ham bo'lmasa STATIK rasm.
                      final vc = ap.controller ?? ap.idleController;
                      if (vc != null && vc.value.isInitialized) {
                        final vs = vc.value.size;
                        return FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: vs.width <= 0 ? 720 : vs.width,
                            height: vs.height <= 0 ? 1280 : vs.height,
                            child: WinVideoPlayer(vc),
                          ),
                        );
                      }
                      return (enabled && url != null)
                          ? Image.network(url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Center(child: kIcon('ai', size: hasData ? 90 : 220, color: Colors.white)))
                          : Center(child: kIcon('ai', size: hasData ? 90 : 220, color: Colors.white));
                    }),
                  ),
                  // HTML .dot: yashil onlayn nuqta (34px + 5px oq chegara, right/bottom 14)
                  if (hasData)
                    Positioned(
                      right: 14 * s,
                      bottom: 14 * s,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF12C56A),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 5),
                        ),
                      ),
                    ),
                ]),
              ),
            ),

            // ======= ESKI QORA-EKRAN boshqaruvlari (salomlashuv/persona holati) =======
            if (!hasData)
              Positioned(
                bottom: 44,
                left: 36,
                child: GestureDetector(
                  onTap: () => context.go('/'),
                  child: Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xEBFFFFFF),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Color(0x38000000), offset: Offset(0, 6), blurRadius: 20)],
                    ),
                    child: const Text('‹', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: T.navy)),
                  ),
                ),
              ),
            if (!hasData)
              Positioned(
                bottom: 170,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => ref.read(voiceProvider.notifier).toggleTalk(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: v.recording ? 172 : 150,
                      height: v.recording ? 172 : 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: v.recording ? const Color(0xFFE5484D) : const Color(0xFF5457F5),
                        boxShadow: [
                          BoxShadow(
                            color: v.recording ? const Color(0x66E5484D) : const Color(0x4D5457F5),
                            blurRadius: 42,
                            spreadRadius: v.recording ? 14 : 4,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(v.recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 78),
                    ),
                  ),
                ),
              ),
            if (!hasData)
              Positioned(
                bottom: 60,
                left: 40,
                right: 40,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xEBFFFFFF),
                      borderRadius: BorderRadius.circular(44),
                      boxShadow: const [BoxShadow(color: Color(0x2410266B), offset: Offset(0, 6), blurRadius: 22)],
                    ),
                    child: Text(_statusOld(v, t),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: T.navy)),
                  ),
                ),
              ),

            // WARMUP qatlami — bilinar-bilinmas 0101 + foiz chizig'i
            if (_isWarmup)
              Positioned.fill(
                child: IgnorePointer(child: _WarmupOverlay(progress: _warmupProgress, dark: !hasData)),
              ),

            // KIRISH (INTRO) VIDEOSI — eng UST qatlam, to'liq ekran (hamma narsani yopadi).
            // O'ynаganда AI gapirmaydi, mikrofon tinglamaydi; tugagach yo'qoladi → savol kutadi.
            if (_introCtl != null && _introCtl!.value.isInitialized)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {}, // teginish intro'ni o'tkazib yubormasin (to'liq ko'rsin)
                  child: ColoredBox(
                    color: Colors.black,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _introCtl!.value.size.width <= 0 ? 1080 : _introCtl!.value.size.width,
                        height: _introCtl!.value.size.height <= 0 ? 1920 : _introCtl!.value.size.height,
                        child: WinVideoPlayer(_introCtl!),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// HTML-mockup sahnasi — 940x1832 DIZAYN BIRLIKLARIDA chiziladi (FittedBox masshtablaydi).
/// Avatar bu sahnaga KIRMAYDI (u tepada AnimatedPositioned bilan "uchib" keladi).
class _MockStage extends ConsumerStatefulWidget {
  const _MockStage({
    required this.t,
    required this.v,
    required this.statusText,
    required this.searchCtrl,
    required this.q,
    required this.onQ,
    required this.onClearQ,
    required this.onAsk,
    required this.onBack,
    required this.onMic,
    required this.onDots,
  });
  final Map<String, dynamic> t;
  final VoiceUiState v;
  final String statusText;
  final TextEditingController searchCtrl;
  final String q;
  final void Function(String) onQ;
  final VoidCallback onClearQ;
  final void Function(String) onAsk;
  final VoidCallback onBack;
  final VoidCallback onMic;
  final VoidCallback onDots;

  @override
  ConsumerState<_MockStage> createState() => _MockStageState();
}

class _MockStageState extends ConsumerState<_MockStage> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    // HTML animatsiyalari: halo 2.6s, to'lqin 1s, dot 2.4s — bitta 5.2s davrdan olinadi.
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Qator uchun palitra: xizmatlarda tartib bo'yicha, jadvalda indeks bo'yicha aylanadi;
  /// ikonka nom mazmuniga qarab (uy/yer/mahalla/bino).
  _Pal _rowPal(String label, int i) {
    final base = _pals[i % _pals.length];
    final l = label.toLowerCase();
    IconData ic = base.icon;
    if (l.contains('mulk') || l.contains('uy') || l.contains('xonadon')) {
      ic = Icons.home_rounded;
    } else if (l.contains('yer') || l.contains('uchastka') || l.contains('maydon')) {
      ic = Icons.location_on_rounded;
    } else if (l.contains('mahalla') || l.contains('aholi')) {
      ic = Icons.groups_rounded;
    } else if (l.contains('tuman') || l.contains('shahar') || l.contains('bino') || l.contains('obyekt')) {
      ic = Icons.apartment_rounded;
    }
    return _Pal(ic, base.iconBg, base.pillBg, base.fg);
  }

  /// Javob matni: RAQAMLAR indigo-bold (HTML uslubidagi urg'u).
  List<TextSpan> _rich(String txt, double fs) {
    final base = TextStyle(fontSize: fs, fontWeight: FontWeight.w500, color: _cInk2, height: 1.55);
    final numS = TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: _cIndigo, height: 1.55);
    final out = <TextSpan>[];
    final re = RegExp(r'\d[\d\s ]*\d|\d');
    var last = 0;
    for (final m in re.allMatches(txt)) {
      if (m.start > last) out.add(TextSpan(text: txt.substring(last, m.start), style: base));
      out.add(TextSpan(text: m.group(0), style: numS));
      last = m.end;
    }
    if (last < txt.length) out.add(TextSpan(text: txt.substring(last), style: base));
    return out;
  }

  String _cell(dynamic v) {
    final s = '$v';
    final n = num.tryParse(s.replaceAll(RegExp(r'[\s ]'), ''));
    return n != null ? fmt(n) : s;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final v = widget.v;

    // Xizmat qatorlari — REAL raqamlar (/stats + /xatlov937 total c9/c10/c16)
    final stats = ref.watch(statsProvider).valueOrNull;
    final xat = ref.watch(xatlov937Provider).valueOrNull;
    final xt = (xat?['total'] is Map) ? Map<String, dynamic>.from(xat!['total'] as Map) : const <String, dynamic>{};
    int? xn(String k) => (xt[k] is num) ? (xt[k] as num).toInt() : null;
    final services = <(String, int?, String)>[
      (t['svcArizalar'], stats?.arizalar, 'Arizalar statistikasi'),
      (t['svcAuksion'], stats?.auksionYerlar, 'Auksion yerlar statistikasi'),
      (t['svcMfy'], xn('c9'), 'Xatlov statistikasi'),
      (t['svcXatlov'], xn('c10'), 'Xatlov obyektlari soni'),
      (t['svcXatlovDone'], xn('c16'), 'Xatlovdan o‘tkazilgan obyektlar soni'),
    ];

    final ql = widget.q.trim().toLowerCase();
    final allRows = v.table ?? const <List<dynamic>>[];
    final headed = allRows.isNotEmpty &&
        allRows[0].length > 1 &&
        num.tryParse('${allRows[0][1]}'.replaceAll(RegExp(r'[\s ]'), '')) == null;
    final body = headed ? allRows.sublist(1) : allRows;
    final hasTable = body.isNotEmpty;
    final rows = ql.isEmpty
        ? body
        : body.where((r) => '${r.isNotEmpty ? r[0] : ''}'.toLowerCase().contains(ql)).toList();
    final svcRows = ql.isEmpty
        ? services
        : services.where((s2) => s2.$1.toLowerCase().contains(ql)).toList();

    final recording = v.recording;
    final micCol1 = recording ? const Color(0xFFE5484D) : const Color(0xFF5B4BF0);
    final micCol2 = recording ? const Color(0xFFC73A3F) : const Color(0xFF4A3FDD);

    final fs = v.answer.length > 200 ? 21.0 : 23.0;

    return Stack(clipBehavior: Clip.hardEdge, children: [
      // ---- orqa fon chiziqlari (HTML .bg-lines) ----
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 640,
        child: IgnorePointer(child: CustomPaint(painter: _BgLinesPainter())),
      ),

      // ---- salomlashuv paneli (teskari radiusli BITTA oq yuza) + JAVOB MATNI ----
      Positioned(
        left: 0,
        top: 0,
        width: _dW,
        height: 560,
        child: IgnorePointer(child: CustomPaint(painter: _PanelPainter())),
      ),
      // Javob matni panel ichida (HTML .panel-top joyi: left 80, top ~165, width 548).
      // Javob bo'sh + suggest bo'lsa — "tushunmadim, tanlang" matni (chala gap holati).
      Positioned(
        left: 80,
        top: 162,
        width: 548,
        height: 178,
        child: SingleChildScrollView(
          child: v.answer.isNotEmpty
              ? RichText(text: TextSpan(children: _rich(v.answer, fs)))
              : Text(t['feSuggest'] ?? 'Kechirasiz, tushunmadim. Quyidagilardan tanlang:',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: _cInk2, height: 1.5)),
        ),
      ),
      // gradient chiziqcha (HTML .rule) — panel pastki qismida aksent
      Positioned(
        left: 80,
        top: 352,
        child: Container(
          width: 56,
          height: 6,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            gradient: LinearGradient(colors: [Color(0xFF5B4BF0), Color(0xFF8B8EF7), Color(0x008B8EF7)]),
          ),
        ),
      ),
      // panel pastki keng qismida davom savoli (HTML .panel-ask uslubi)
      Positioned(
        left: 80,
        top: 374,
        width: 740,
        child: Text(t['aiAsk'],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 23, height: 1.55, fontWeight: FontWeight.w400, color: _cInk2)),
      ),

      // ---- orqaga tugmasi (36,42,72x72,r21) ----
      Positioned(
        left: 36,
        top: 42,
        child: _SqBtn(
          size: 72,
          radius: 21,
          onTap: widget.onBack,
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF16224A), size: 26),
        ),
      ),

      // ---- qidiruv (36,500,869x102,r26) ----
      Positioned(
        left: 36,
        top: 500,
        width: 869,
        height: 102,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [BoxShadow(color: Color(0x0F3C5096), offset: Offset(0, 8), blurRadius: 28)],
          ),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: Color(0xFF8F97B2), size: 34),
            const SizedBox(width: 22),
            Expanded(
              child: TextField(
                controller: widget.searchCtrl,
                onChanged: widget.onQ,
                onSubmitted: widget.onAsk,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w500, color: _cInk),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: t['aiSearch'],
                  hintStyle: const TextStyle(fontSize: 25, fontWeight: FontWeight.w500, color: Color(0xFFA7AEC6)),
                ),
              ),
            ),
            GestureDetector(
              onTap: widget.q.isEmpty ? null : widget.onClearQ,
              child: Icon(widget.q.isEmpty ? Icons.tune_rounded : Icons.close_rounded,
                  color: const Color(0xFF5B6A9A), size: 30),
            ),
          ]),
        ),
      ),

      // ---- bo'lim sarlavhasi (57,636) ----
      Positioned(
        left: 57,
        top: 636,
        child: Text(t['aiServices'],
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: _cInk)),
      ),

      // ---- ro'yxat (36,686,869; qator 116, oraliq 14) ----
      Positioned(
        left: 36,
        top: 686,
        width: 869,
        height: 640,
        child: ListView(
          padding: EdgeInsets.zero,
          children: hasTable
              ? [
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('Topilmadi',
                            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600, color: _cMuted)),
                      ),
                    ),
                  for (var i = 0; i < rows.length; i++)
                    _row(
                      _rowPal('${rows[i].isNotEmpty ? rows[i][0] : ''}', i),
                      '${rows[i].isNotEmpty ? rows[i][0] : ''}',
                      rows[i].length > 1 ? _cell(rows[i][1]) : '',
                      () => widget.onAsk('${rows[i].isNotEmpty ? rows[i][0] : ''} statistikasi'),
                    ),
                ]
              : [
                  for (var i = 0; i < svcRows.length; i++)
                    _row(
                      _rowPal(svcRows[i].$1, i),
                      svcRows[i].$1,
                      svcRows[i].$2 == null ? '…' : fmt(svcRows[i].$2!),
                      () => widget.onAsk(svcRows[i].$3),
                    ),
                ],
        ),
      ),

      // ---- mikrofon (markaz 470,1449; halo 190/150; tugma 126 gradient) ----
      Positioned(
        left: _dW / 2 - 100,
        top: 1449 - 100,
        width: 200,
        height: 200,
        child: GestureDetector(
          onTap: widget.onMic,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) {
              // HTML @keyframes halo: 2.6s davr, scale .92 -> 1.06
              final ph = (_anim.value * 2.0) % 1.0; // 5.2s / 2 = 2.6s
              final sc1 = 0.99 + 0.07 * math.sin(ph * 2 * math.pi);
              final ph2 = ((_anim.value * 2.0) + 0.19) % 1.0; // .5s kechikish
              final sc2 = 0.99 + 0.07 * math.sin(ph2 * 2 * math.pi);
              return Stack(alignment: Alignment.center, children: [
                Transform.scale(
                  scale: sc1,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (recording ? const Color(0xFFE5484D) : const Color(0xFF635BEB)).withOpacity(0.13)),
                  ),
                ),
                Transform.scale(
                  scale: sc2,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (recording ? const Color(0xFFE5484D) : const Color(0xFF635BEB)).withOpacity(0.18)),
                  ),
                ),
                Container(
                  width: 126,
                  height: 126,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [micCol1, micCol2]),
                    boxShadow: [
                      BoxShadow(
                          color: (recording ? const Color(0xFFE5484D) : const Color(0xFF4F46E5)).withOpacity(0.42),
                          offset: const Offset(0, 16),
                          blurRadius: 34),
                    ],
                  ),
                  child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 58),
                ),
              ]);
            },
          ),
        ),
      ),

      // ---- '...' tugmasi (36,1546,72x72,r21) ----
      Positioned(
        left: 36,
        top: 1546,
        child: _SqBtn(
          size: 72,
          radius: 21,
          onTap: widget.onDots,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(color: _cInk, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),

      // ---- status pilli (markaz, top 1582, h62, r31) — animatsion to'lqin + matn ----
      Positioned(
        left: 0,
        right: 0,
        top: 1582,
        child: Center(
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(31),
              boxShadow: const [BoxShadow(color: Color(0x173C5096), offset: Offset(0, 8), blurRadius: 26)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) {
                  // HTML @keyframes wv: 1s davr, balandlik 8 -> 24, 4 ta ustun .15s kechikish
                  final base = _anim.value * 5.2; // soniya
                  return SizedBox(
                    height: 26,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          width: 5,
                          height: 8 + 16 * (0.5 + 0.5 * math.sin(((base - i * 0.15) % 1.0) * 2 * math.pi)),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: _cIndigo,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ]),
                  );
                },
              ),
              const SizedBox(width: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(widget.statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: _cInk)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// HTML .row: 116px, r24, ico 74 r21, nom 25/600, son-pill h47 r13, chevron.
  Widget _row(_Pal p, String name, String count, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 116,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.only(left: 28, right: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x0E3C5096), offset: Offset(0, 8), blurRadius: 24)],
        ),
        child: Row(children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(color: p.iconBg, borderRadius: BorderRadius.circular(21)),
            child: Icon(p.icon, color: p.fg, size: 40),
          ),
          const SizedBox(width: 37),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600, color: _cInk)),
          ),
          const SizedBox(width: 14),
          Container(
            height: 47,
            constraints: const BoxConstraints(minWidth: 110),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.pillBg, borderRadius: BorderRadius.circular(13)),
            child: Text(count,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.fg, letterSpacing: 0.2)),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.chevron_right_rounded, color: _cMuted, size: 28),
        ]),
      ),
    );
  }
}

/// Oq kvadrat tugma (orqaga / '...') — HTML .back/.dots uslubi.
class _SqBtn extends StatelessWidget {
  const _SqBtn({required this.size, required this.radius, required this.onTap, required this.child});
  final double size, radius;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [BoxShadow(color: Color(0x143C5096), offset: Offset(0, 6), blurRadius: 20)],
        ),
        child: child,
      ),
    );
  }
}

/// HTML .panel-bg: teskari-radiusli oq panel (avatar atrofida 130px botiq yoy).
/// Path koordinatalari kadastr-kiosk.html'dan AYNAN.
class _PanelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(64, 130)
      ..lineTo(632, 130)
      ..arcToPoint(const Offset(660, 158), radius: const Radius.circular(28))
      ..lineTo(660, 205)
      ..arcToPoint(const Offset(790, 335), radius: const Radius.circular(130), clockwise: false)
      ..lineTo(877, 335)
      ..arcToPoint(const Offset(905, 363), radius: const Radius.circular(28))
      ..lineTo(905, 434)
      ..arcToPoint(const Offset(877, 462), radius: const Radius.circular(28))
      ..lineTo(64, 462)
      ..arcToPoint(const Offset(36, 434), radius: const Radius.circular(28))
      ..lineTo(36, 158)
      ..arcToPoint(const Offset(64, 130), radius: const Radius.circular(28))
      ..close();
    // soya (HTML feDropShadow: dy 8, blur ~14, #3c5096 7%)
    canvas.drawPath(
      path.shift(const Offset(0, 8)),
      Paint()
        ..color = const Color(0x123C5096)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PanelPainter old) => false;
}

/// HTML .bg-lines: pastdagi 3 ta yengil dekorativ yoy.
class _BgLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint st(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final w = size.width, h = size.height;
    final p1 = Path()
      ..moveTo(-60, h)
      ..cubicTo(-60, h - 260, 180, h - 340, w / 2, h - 340)
      ..cubicTo(w - 180, h - 340, w + 60, h - 260, w + 60, h);
    final p2 = Path()
      ..moveTo(-60, h + 60)
      ..cubicTo(-60, h - 220, 200, h - 295, w / 2, h - 295)
      ..cubicTo(w - 200, h - 295, w + 60, h - 220, w + 60, h + 60);
    final p3 = Path()
      ..moveTo(120, h)
      ..cubicTo(120, h - 170, 270, h - 250, w / 2, h - 250)
      ..cubicTo(w - 270, h - 250, w - 120, h - 170, w - 120, h);
    canvas.drawPath(p1, st(const Color(0xFFDFE5F7)));
    canvas.drawPath(p2, st(const Color(0xFFE5EAF8)));
    canvas.drawPath(p3, st(const Color(0xFFE7EBF9)));
  }

  @override
  bool shouldRepaint(_BgLinesPainter old) => false;
}

/// AIга kirganда ustidан BILINAR-BILINMAS ko'rinadigan qatlam: Matrix uslubidagi
/// "0101" binary yomg'iri + pastda 5 soatда to'ladigan juda xira chiziq + kichkina foiz.
/// IgnorePointer bilan o'raladi (AI ostidan normal ishlaydi).
class _WarmupOverlay extends StatefulWidget {
  const _WarmupOverlay({required this.progress, required this.dark});
  final double progress; // 0..100
  final bool dark; // to'q fon (avatar to'liq ekran) — yashilroq; och fon (karta) — xiraroq
  @override
  State<_WarmupOverlay> createState() => _WarmupOverlayState();
}

class _WarmupOverlayState extends State<_WarmupOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bilinar-bilinmas: to'q fonда 0.10, och fonда 0.06 shaffoflik.
    final op = widget.dark ? 0.11 : 0.06;
    return Stack(children: [
      Positioned.fill(
        child: Opacity(
          opacity: op,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(painter: _BinaryRainPainter(_c.value), size: Size.infinite),
            ),
          ),
        ),
      ),
      // 5 soatда to'ladigan JUDA XIRA chiziq (eng pastда) + kichkina foiz
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: widget.dark ? 0.22 : 0.14,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14, bottom: 4),
                  child: Text('${widget.progress.round()}%',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: widget.dark ? Colors.greenAccent : const Color(0xFF2E7D5B))),
                ),
              ),
            ),
            SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: (widget.progress / 100.0).clamp(0.0, 1.0),
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(
                    (widget.dark ? Colors.greenAccent : const Color(0xFF2E7D5B)).withOpacity(0.25)),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Matrix "0101" yomg'iri — ustundan pastga tushuvchi binary raqamlar (barqaror naqsh,
/// faqat siljiydi — miltillamaydi). PERF: '0' va '1' BIR MARTA layout qilinib qayta
/// chiziladi (har freymда layout QILINMAYDI) — kiosk GPU'siga yengil.
class _BinaryRainPainter extends CustomPainter {
  _BinaryRainPainter(this.t);
  final double t; // 0..1 (siljish fazasi)
  static const int _cols = 26;
  static const double _cell = 36;

  static final TextPainter _p0 = _mk('0');
  static final TextPainter _p1 = _mk('1');
  static TextPainter _mk(String ch) => TextPainter(
        text: TextSpan(
          text: ch,
          style: const TextStyle(color: Color(0xFF39FF9A), fontSize: 22, fontFamily: 'monospace', fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  // (c, row) uchun BARQAROR raqam (0/1) — determinlashgan psevdo-tasodif (miltillamaydi).
  int _bit(int c, int row) => (((c * 73856093) ^ (row * 19349663)) >> 5) & 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final colW = size.width / _cols;
    final rowsPerCol = (size.height / _cell).ceil() + 2;
    for (var c = 0; c < _cols; c++) {
      final speed = 0.6 + ((c * 37) % 7) * 0.12; // ustunlar turli tezlikda (barqaror)
      final offset = (t * speed % 1.0) * size.height;
      final x = c * colW + colW / 2;
      for (var d = 0; d < rowsPerCol; d++) {
        final baseY = d * _cell + offset;
        final y = baseY % (size.height + _cell) - _cell;
        final row = (baseY ~/ _cell) + c; // siljiганda raqam o'zgaradi
        final tp = _bit(c, row) == 0 ? _p0 : _p1;
        tp.paint(canvas, Offset(x - tp.width / 2, y));
      }
    }
  }

  @override
  bool shouldRepaint(_BinaryRainPainter old) => old.t != t;
}
