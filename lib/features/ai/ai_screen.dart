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
    if (loading) {
      _speakWarmup(w);
      _warmupPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshWarmup());
    } else {
      final t = I18N[ref.read(localeProvider)]!;
      final vc = ref.read(voiceProvider.notifier);
      vc.resetConversation(); // eski javob/jadval tozalanadi — avatar to'liq ekranda salomlashadi
      vc.greet(t['aiGreet']);
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

  void _speakWarmup(Map<String, dynamic> w) {
    final rem = (w['remaining'] as num?)?.round() ?? 100;
    // "Har kirganda buncha foiz qoldi deb gapirsin" — boshqa gap qo'shilmaydi.
    ref.read(voiceProvider.notifier).greet('Hozirda sun\'iy intellekt yuklanmoqda. $rem foiz qoldi.');
  }

  @override
  void dispose() {
    _warmupPoll?.cancel();
    ref.read(aiWarmupLoadingProvider.notifier).state = false;
    super.dispose();
  }

  // ── AI "YUKLANMOQDA" ekrani — orqada avatar, markazда foizli progress ──
  Widget _buildWarmup(Map<String, dynamic> w) {
    final avatar = ref.watch(avatarProvider).valueOrNull;
    final url = (avatar?.enabled ?? false) ? '${Env.apiBase}/avatar/file?${avatar!.imageQuery}' : null;
    final loaded = ((w['progress'] as num?)?.toDouble() ?? 0).clamp(0, 100).toDouble();
    final remaining = (w['remaining'] as num?)?.round() ?? (100 - loaded).round();
    return Container(
      color: T.aiDark,
      child: Stack(fit: StackFit.expand, children: [
        // Avatar ORQADA (to'liq ekran, xiralashtirilgan)
        if (url != null)
          Opacity(opacity: 0.45, child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.30), Colors.black.withOpacity(0.78)]))),
        // Markaz: halqa (yuklangan foiz to'ladi) + markazда QOLGAN foiz
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 340, height: 340, child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 340, height: 340, child: CircularProgressIndicator(
              value: loaded / 100.0, strokeWidth: 18,
              backgroundColor: Colors.white.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(T.green))),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$remaining%', style: const TextStyle(color: Colors.white, fontSize: 104, fontWeight: FontWeight.w900, height: 1.0)),
              const Text('qoldi', style: TextStyle(color: Colors.white70, fontSize: 30, fontWeight: FontWeight.w600)),
            ]),
          ])),
          const SizedBox(height: 48),
          const Text('Sun\'iy intellekt yuklanmoqda', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          SizedBox(width: 520, child: LinearProgressIndicator(
            value: loaded / 100.0, minHeight: 12,
            backgroundColor: Colors.white.withOpacity(0.15),
            valueColor: const AlwaysStoppedAnimation(T.green))),
        ])),
      ]),
    );
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
    if (_isWarmup) return _buildWarmup(_warmup!);
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
            // exit pill
            Positioned(
              top: 28,
              left: 28,
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
          ],
        );
      }),
    );
  }
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
