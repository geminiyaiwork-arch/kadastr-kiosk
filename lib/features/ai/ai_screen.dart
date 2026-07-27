import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});
  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  // Burchakka chiqish spin'i FAQAT OLDINGA aylansin: har chiqishda +1 tur.
  // (turns butun son bo'lgach, to'liq holatda vizual farq yo'q; orqaga
  // qaytishda teskari 360° aylanish bo'lmaydi.)
  bool _wasCorner = false;
  int _spins = 0;

  // AI "yuklanmoqda" (7 soatlik foizli) holati
  Map<String, dynamic>? _warmup;
  Timer? _warmupPoll;
  bool get _isWarmup => _warmup != null && _warmup!['loading'] == true;

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
    // AI HAR DOIM normal ishlaydi + salomlashadi. Warmup faqat ustidан bilinar-bilinmas
    // 0101 qatlam (bloklamaydi, ovozда e'lon qilmaydi — "hech nimaga ta'sir qilmasin").
    final t = I18N[ref.read(localeProvider)]!;
    final vc = ref.read(voiceProvider.notifier);
    vc.resetConversation(); // eski javob/jadval tozalanadi — avatar to'liq ekranda salomlashadi
    vc.greet(t['aiGreet']);
    if (loading) {
      _warmupPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshWarmup());
    }
  }

  Future<void> _refreshWarmup() async {
    Map<String, dynamic> w;
    try { w = Map<String, dynamic>.from((await ref.read(dioProvider).get('/ai/warmup')).data as Map); } catch (_) { return; }
    if (!mounted) return;
    final loading = w['loading'] == true;
    ref.read(aiWarmupLoadingProvider.notifier).state = loading;
    setState(() => _warmup = w);
    if (!loading) { _warmupPoll?.cancel(); } // 7 soat tugadi → AI normal ishga tushadi
  }

  // Warmup to'lish foizi (0→100, 5 soatда). Server `progress` qaytaradi.
  double get _warmupProgress => ((_warmup?['progress'] as num?)?.toDouble() ?? 0).clamp(0, 100).toDouble();

  @override
  void dispose() {
    _warmupPoll?.cancel();
    ref.read(aiWarmupLoadingProvider.notifier).state = false;
    super.dispose();
  }


  String _status(VoiceUiState v, Map<String, dynamic> t) {
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

  static const _fx = Duration(milliseconds: 520);
  static const _fxCurve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    // WARMUP endi BLOKLAMAYDI — AI to'liq ishlaydi, warmup faqat ustidan bilinar-bilinmas
    // 0101 qatlam (pastda Stack ichiga qo'shiladi).
    final t = ref.watch(trProvider);
    final v = ref.watch(voiceProvider);
    final avatar = ref.watch(avatarProvider).valueOrNull;
    final enabled = avatar?.enabled ?? false;
    final url = enabled
        ? '${Env.apiBase}/avatar/file?${avatar!.imageQuery}'
        : null; // /api/v1 bilan (resolveMedia 404 berardi); video bo'lsa idle jpg
    // JIM-HOLAT imo-ishora videosi tayyorlansin (Windows; bir marta yuklanadi)
    if (enabled) ref.read(avatarPlayerProvider.notifier).ensureIdle(avatar);
    final hasData = v.answer.isNotEmpty;

    return AnimatedContainer(
      duration: _fx,
      color: hasData ? const Color(0xFFEFF1FA) : T.aiDark, // javobda OCH fon (mockup)
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        // Avatar holatlari:
        //  GAPIRAYOTGANDA (lab-sinx video) -> TO'LIQ EKRAN (video 9:16, kanvas 9:16 —
        //  bosh kesilmaydi; kvadrat qutida boshi kesilardi)
        //  javob bor (jim)                 -> yuqori-o'ng burchakda kichik DUMALOQ
        //  javob yo'q (jim)                -> TO'LIQ ekran (rasm)
        const corner = 210.0;
        final ap = ref.watch(avatarPlayerProvider); // video boshlanganda rebuild (Builder controllerni oladi)
        // MA'LUMOTLI javob -> avatar BURCHAKDA (gapirayotganda ham — video doirada),
        // javob ekranda ko'rinib turadi. Ma'lumotsiz (salomlashuv/persona) -> TO'LIQ ekran.
        final rect = hasData
            ? Rect.fromLTWH(w - corner - 30, 30, corner, corner)
            : Rect.fromLTWH(0, 0, w, h);
        final cornerNow = hasData;
        if (cornerNow && !_wasCorner) _spins++; // burchakka chiqishda bir tur oldinga
        _wasCorner = cornerNow;
        return Stack(
          children: [
            // dumaloq/to'liq avatar — bitta widget, o'lchami-joyi ANIMATSIYA bilan o'zgaradi.
            // Burchakka chiqishda QUSHDAY bir marta aylanib "uchib" boradi.
            AnimatedPositioned(
              duration: _fx,
              curve: _fxCurve,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
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
                    borderRadius: BorderRadius.circular(hasData ? corner / 2 : 0),
                    border: hasData
                        ? Border.all(color: v.speaking ? const Color(0xFF5457F5) : Colors.white, width: 5)
                        : null,
                    boxShadow: v.speaking
                        ? [const BoxShadow(color: Color(0x732F6FE3), blurRadius: 46, spreadRadius: 6)]
                        : (hasData
                            ? [const BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))]
                            : null),
                  ),
                  child: Builder(builder: (context) {
                    // MULOQAT javobida (salom/persona) LAB-SINXRON video generatsiya qilinadi
                    // (video_player_win = Windows Media Foundation, SAC-xavfsiz). Video faol
                    // bo'lsa — to'liq ekran; aks holda STATIK avatar rasmi (ma'lumotli javob:
                    // avatar burchakda statik, ovoz TTS).
                    final vc = ap.controller;
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
                                Center(child: kIcon('ai', size: hasData ? 100 : 220, color: Colors.white)))
                        : Center(child: kIcon('ai', size: hasData ? 100 : 220, color: Colors.white));
                  }),
                  ),
                  if (hasData)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            // JAVOB maydoni — matn + jadval KATTA ekranda. Video gapirayotganda
            // YASHIRIN (video to'liq ekran); gapirib bo'lgach chiqadi.
            Positioned(
              top: 30,
              left: 36,
              right: hasData ? corner + 76 : 36,
              bottom: 330,
              child: IgnorePointer(
                ignoring: !hasData,
                child: AnimatedOpacity(
                  duration: _fx,
                  curve: _fxCurve,
                  opacity: hasData ? 1 : 0,
                  child: AnimatedSlide(
                    duration: _fx,
                    curve: _fxCurve,
                    offset: hasData ? Offset.zero : const Offset(0, 0.06),
                    child: hasData ? _AnswerView(text: v.answer, table: v.table) : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            // exit pill — PASTKI-CHAPDA (avval top-left'da javob matni ustiga chiqib qolardi)
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
            // TAP-TO-TALK mikrofon tugmasi — VAD'siz, hamma platformada (Linux ham) ishlaydi
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
            // status pill
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
                  child: Text(_status(v, t),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: T.navy)),
                ),
              ),
            ),
            // WARMUP qatlami — bilinar-bilinmas 0101 binary yomg'iri + 5 soatда to'ladigan
            // ingichka chiziq. IgnorePointer → AI ostidan NORMAL ishlaydi, hech nimaga ta'sir yo'q.
            if (_isWarmup)
              Positioned.fill(
                child: IgnorePointer(child: _WarmupOverlay(progress: _warmupProgress, dark: !hasData)),
              ),
          ],
        );
      }),
    );
  }
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

/// MOCKUP (1:1) uslubidagi javob: OLOV-belgili + raqamlari INDIGO-BOLD matn-karta,
/// QIDIRUV maydoni ("Tuman yoki shahar nomini qidiring...") + har qatori RANGLI
/// IKONKA-BELGILI + KO'K SON + chevron ro'yxat (Nomi | Soni), yumaloq oq kartalar.
/// StatefulWidget \u2014 qidiruv ro'yxatni jonli filtrlaydi.
class _AnswerView extends StatefulWidget {
  const _AnswerView({required this.text, required this.table});
  final String text;
  final List<List<dynamic>>? table;

  @override
  State<_AnswerView> createState() => _AnswerViewState();
}

class _AnswerViewState extends State<_AnswerView> {
  static const _ink = Color(0xFF232A4D);
  static const _indigo = Color(0xFF5457F5);

  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void didUpdateWidget(covariant _AnswerView old) {
    super.didUpdateWidget(old);
    // Yangi javob kelsa qidiruv tozalanadi (eski filtr yopishib qolmasin).
    if (old.text != widget.text) {
      _q = '';
      _searchCtrl.clear();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _cell(dynamic v) {
    final s = '$v';
    final n = num.tryParse(s.replaceAll(RegExp(r'[\s\u00A0]'), ''));
    return n != null ? fmt(n) : s;
  }

  /// Matndagi RAQAMLAR indigo-bold bo'lib ajraladi (mockupdagidek).
  List<TextSpan> _rich(String t, double fs) {
    final base = TextStyle(fontSize: fs, fontWeight: FontWeight.w600, color: _ink, height: 1.45);
    final numS = TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: _indigo, height: 1.45);
    final out = <TextSpan>[];
    final re = RegExp(r'\d[\d\s\u00A0]*\d|\d');
    var last = 0;
    for (final m in re.allMatches(t)) {
      if (m.start > last) out.add(TextSpan(text: t.substring(last, m.start), style: base));
      out.add(TextSpan(text: m.group(0), style: numS));
      last = m.end;
    }
    if (last < t.length) out.add(TextSpan(text: t.substring(last), style: base));
    return out;
  }

  /// Qator uchun mavzuga mos ikonka + rang (mockup: bino/uy/pin/odamlar).
  (IconData, Color, Color) _badge(String label, int i) {
    final l = label.toLowerCase();
    if (l.contains('mulk') || l.contains('uy') || l.contains('xonadon')) {
      return (Icons.home_rounded, const Color(0xFFE3F0FE), const Color(0xFF2E90FA));
    }
    if (l.contains('yer') || l.contains('uchastka') || l.contains('maydon')) {
      return (Icons.location_on_rounded, const Color(0xFFE2F8EC), const Color(0xFF16B364));
    }
    if (l.contains('aholi') || l.contains('mahalla')) {
      return (Icons.groups_rounded, const Color(0xFFEDE7FE), const Color(0xFF7C5CFC));
    }
    // tuman/shahar/bino/xatlov/ariza \u2014 asosiy hol: bino ikonasi (mockupdagidek)
    return (Icons.apartment_rounded, const Color(0xFFE7ECFE), const Color(0xFF3B5BFE));
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final allRows = widget.table ?? const <List<dynamic>>[];
    final hasTable = allRows.isNotEmpty;
    final headed = allRows.isNotEmpty &&
        allRows[0].length > 1 &&
        num.tryParse('${allRows[0][1]}'.replaceAll(RegExp(r'[\s\u00A0]'), '')) == null;
    final header = headed ? allRows[0] : const <dynamic>['Nomi', 'Soni'];
    final bodyAll = headed ? allRows.sublist(1) : allRows;
    // QIDIRUV filtri \u2014 nom bo'yicha (bo'sh so'rov\u0434\u0430 hammasi).
    final ql = _q.trim().toLowerCase();
    final body = ql.isEmpty
        ? bodyAll
        : bodyAll.where((r) => '${r.isNotEmpty ? r[0] : ''}'.toLowerCase().contains(ql)).toList();
    final fs = text.length > 220 ? 27.0 : 31.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1) MATN: kichik OLOV ikonasi (ko'k gradient) + raqamlari ko'k-bold matn.
        //    Mockup 1:1 — KARTASIZ (matn to'g'ridan-to'g'ri och fonда), avatar yuqori-o'ngда.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0xFF4B7BFF), Color(0xFF7C5CFC)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(r),
                  child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: RichText(text: TextSpan(children: _rich(text, fs)))),
            ],
          ),
        ),
        if (hasTable) ...[
          const SizedBox(height: 20),
          // 2) QIDIRUV maydoni \u2014 "Tuman yoki shahar nomini qidiring..."
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x1229306B), offset: Offset(0, 5), blurRadius: 18)],
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF9AA1C7), size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _q = v),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: _ink),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 22),
                      border: InputBorder.none,
                      hintText: 'Tuman yoki shahar nomini qidiring...',
                      hintStyle: TextStyle(fontSize: 25, fontWeight: FontWeight.w500, color: Color(0xFFAAB0D0)),
                    ),
                  ),
                ),
                // Mockup 1:1: o'ngда sliders(filter) ikonasi; yozilганда X (tozalash)
                GestureDetector(
                  onTap: _q.isEmpty
                      ? null
                      : () => setState(() {
                            _q = '';
                            _searchCtrl.clear();
                          }),
                  child: Icon(_q.isEmpty ? Icons.tune_rounded : Icons.close_rounded,
                      color: const Color(0xFF9AA1C7), size: 28),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // 3) RO'YXAT \u2014 ikonka + nom + ko'k son + chevron
          Flexible(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [BoxShadow(color: Color(0x1A29306B), offset: Offset(0, 8), blurRadius: 26)],
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      color: const Color(0xFFE4E6F9),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text('${header.isNotEmpty ? header[0] : 'Nomi'}',
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink))),
                          Text('${header.length > 1 ? header[1] : 'Soni'}',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink)),
                        ],
                      ),
                    ),
                    if (body.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text('Topilmadi',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFF9AA1C7))),
                      ),
                    for (var i = 0; i < body.length; i++)
                      Builder(builder: (context) {
                        final label = '${body[i].isNotEmpty ? body[i][0] : ''}';
                        final b = _badge(label, i);
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEDEFF9)))),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(color: b.$2, borderRadius: BorderRadius.circular(16)),
                                child: Icon(b.$1, color: b.$3, size: 32),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                  child: Text(label,
                                      style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w600, color: _ink))),
                              const SizedBox(width: 14),
                              Text(body[i].length > 1 ? _cell(body[i][1]) : '',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _indigo)),
                              const SizedBox(width: 12),
                              const Icon(Icons.chevron_right_rounded, color: Color(0xFFC2C8E4), size: 34),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
