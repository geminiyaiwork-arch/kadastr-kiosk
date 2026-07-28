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
import '../../core/util/fmt.dart';
import 'voice_controller.dart';

/// AI sahifa — MOCKUP 1:1 (2026-07-28): och fon, salomlashuv kartasi + yuqori-o'ngda
/// dumaloq avatar (yashil onlayn nuqta, gapirganda video shu doirada), qidiruv,
/// "Kadastr xizmatlari" ro'yxati (real /stats + /xatlov937 raqamlari), pastda katta
/// mikrofon + "Javob beryapman..." status pilli. Javob kelganda xizmatlar o'rnida
/// javob matni (olov + indigo raqamlar) va jadval qatorlari chiqadi.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});
  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  static const _bg = Color(0xFFEEF1FA);
  static const _ink = Color(0xFF232A4D);
  static const _slate = Color(0xFF6C7395);
  static const _indigo = Color(0xFF5457F5);
  static const _hintCol = Color(0xFFAAB0D0);

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
    if (!loading) { _warmupPoll?.cancel(); }
  }

  double get _warmupProgress => ((_warmup?['progress'] as num?)?.toDouble() ?? 0).clamp(0, 100).toDouble();

  @override
  void dispose() {
    _warmupPoll?.cancel();
    ref.read(aiWarmupLoadingProvider.notifier).state = false;
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _q = '';
    _searchCtrl.clear();
  }

  /// Yozib yuborilgan (qidiruv) yoki xizmat kartasidan kelgan savol.
  void _ask(String q) {
    final s = q.trim();
    if (s.length < 2) return;
    final vc = ref.read(voiceProvider.notifier);
    vc.stopSpeaking();
    setState(_clearSearch);
    vc.askAI(s);
  }

  String _statusText(VoiceUiState v, Map<String, dynamic> t) {
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

  String _cell(dynamic v) {
    final s = '$v';
    final n = num.tryParse(s.replaceAll(RegExp(r'[\s ]'), ''));
    return n != null ? fmt(n) : s;
  }

  /// Matndagi RAQAMLAR indigo-bold bo'lib ajraladi (mockupdagidek).
  List<TextSpan> _rich(String t, double fs) {
    final base = TextStyle(fontSize: fs, fontWeight: FontWeight.w600, color: _ink, height: 1.45);
    final numS = TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: _indigo, height: 1.45);
    final out = <TextSpan>[];
    final re = RegExp(r'\d[\d\s ]*\d|\d');
    var last = 0;
    for (final m in re.allMatches(t)) {
      if (m.start > last) out.add(TextSpan(text: t.substring(last, m.start), style: base));
      out.add(TextSpan(text: m.group(0), style: numS));
      last = m.end;
    }
    if (last < t.length) out.add(TextSpan(text: t.substring(last), style: base));
    return out;
  }

  /// Jadval qatori uchun mavzuga mos ikonka + rang (mockup: hujjat/pin/uy/bino).
  (IconData, Color, Color) _badge(String label) {
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
    return (Icons.apartment_rounded, const Color(0xFFE7ECFE), const Color(0xFF3B5BFE));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final v = ref.watch(voiceProvider);
    final avatar = ref.watch(avatarProvider).valueOrNull;
    final enabled = avatar?.enabled ?? false;
    final url = enabled ? '${Env.apiBase}/avatar/file?${avatar!.imageQuery}' : null;
    if (enabled) ref.read(avatarPlayerProvider.notifier).ensureIdle(avatar);
    final ap = ref.watch(avatarPlayerProvider);
    final stats = ref.watch(statsProvider).valueOrNull;
    final xat = ref.watch(xatlov937Provider).valueOrNull;
    final hasData = v.answer.isNotEmpty;

    // Yangi javob kelsa qidiruv tozalanadi (eski filtr yopishib qolmasin)
    ref.listen(voiceProvider.select((s) => s.answer), (prev, next) {
      if (prev != next && mounted) setState(_clearSearch);
    });

    // Xizmat kartalari — REAL raqamlar (/stats + /xatlov937 total c9/c10/c16)
    final xt = (xat?['total'] is Map) ? Map<String, dynamic>.from(xat!['total'] as Map) : const <String, dynamic>{};
    int? xn(String k) => (xt[k] is num) ? (xt[k] as num).toInt() : null;
    final services = <_Svc>[
      _Svc(Icons.description_rounded, const Color(0xFFE3F0FE), const Color(0xFF2E90FA),
          t['svcArizalar'], stats?.arizalar, 'Arizalar statistikasi'),
      _Svc(Icons.location_on_rounded, const Color(0xFFE2F8EC), const Color(0xFF16B364),
          t['svcAuksion'], stats?.auksionYerlar, 'Auksion yerlar statistikasi'),
      _Svc(Icons.home_work_rounded, const Color(0xFFEDE7FE), const Color(0xFF7C5CFC),
          t['svcMfy'], xn('c9'), 'Xatlov statistikasi'),
      _Svc(Icons.apartment_rounded, const Color(0xFFE7ECFE), const Color(0xFF3B5BFE),
          t['svcXatlov'], xn('c10'), 'Xatlov obyektlari soni'),
      _Svc(Icons.fmd_good_rounded, const Color(0xFFFEF0E3), const Color(0xFFF79009),
          t['svcXatlovDone'], xn('c16'), 'Xatlovdan o‘tkazilgan obyektlar soni'),
    ];

    final ql = _q.trim().toLowerCase();

    // Javob jadvali (bo'lsa)
    final allRows = v.table ?? const <List<dynamic>>[];
    final headed = allRows.isNotEmpty &&
        allRows[0].length > 1 &&
        num.tryParse('${allRows[0][1]}'.replaceAll(RegExp(r'[\s ]'), '')) == null;
    final body = headed ? allRows.sublist(1) : allRows;
    final rows = ql.isEmpty
        ? body
        : body.where((r) => '${r.isNotEmpty ? r[0] : ''}'.toLowerCase().contains(ql)).toList();
    final svcRows = ql.isEmpty ? services : services.where((s) => s.label.toLowerCase().contains(ql)).toList();

    return Container(
      color: _bg,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 36, 36, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Orqaga (yuqori-chap, mockup)
                Row(children: [
                  _SquareBtn(
                    onTap: () => context.go('/'),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink, size: 36),
                  ),
                ]),
                const SizedBox(height: 22),
                // Salomlashuv (yoki javob matni) + dumaloq avatar
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: hasData ? _answerHead(v.answer) : _greeting(t)),
                    const SizedBox(width: 22),
                    _AvatarCircle(url: url, ap: ap, speaking: v.speaking, fallbackHasImg: enabled),
                  ],
                ),
                const SizedBox(height: 26),
                // Qidiruv
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [BoxShadow(color: Color(0x1229306B), offset: Offset(0, 5), blurRadius: 18)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: Color(0xFF9AA1C7), size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (s) => setState(() => _q = s),
                          onSubmitted: _ask,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: _ink),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 30),
                            border: InputBorder.none,
                            hintText: t['aiSearch'],
                            hintStyle: const TextStyle(fontSize: 27, fontWeight: FontWeight.w500, color: _hintCol),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _q.isEmpty ? null : () => setState(_clearSearch),
                        child: Icon(_q.isEmpty ? Icons.tune_rounded : Icons.close_rounded,
                            color: const Color(0xFF9AA1C7), size: 32),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                // Bo'lim sarlavhasi
                Text(hasData ? t['aiResults'] : t['aiServices'],
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(height: 16),
                // Ro'yxat — xizmatlar (bosh holat) yoki javob jadvali
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 470),
                    children: hasData
                        ? [
                            if (rows.isEmpty && body.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Center(
                                  child: Text('Topilmadi',
                                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFF9AA1C7))),
                                ),
                              ),
                            for (final r in rows) _tableRow(r),
                          ]
                        : [for (final s in svcRows) _svcRow(s)],
                  ),
                ),
              ],
            ),
          ),
          // Katta mikrofon (pastki markaz) — halo bilan
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => ref.read(voiceProvider.notifier).toggleTalk(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: v.recording ? 268 : 252,
                  height: v.recording ? 268 : 252,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (v.recording ? const Color(0xFFE5484D) : _indigo).withOpacity(0.10),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 208,
                    height: 208,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (v.recording ? const Color(0xFFE5484D) : _indigo).withOpacity(0.16),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 164,
                      height: 164,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: v.recording ? const Color(0xFFE5484D) : _indigo,
                        boxShadow: [
                          BoxShadow(
                            color: v.recording ? const Color(0x66E5484D) : const Color(0x4D5457F5),
                            blurRadius: 38,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(v.recording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white, size: 82),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // "..." tugmasi (pastki-chap, mockup) — suhbatni tozalaydi/ovoz to'xtatadi
          Positioned(
            bottom: 64,
            left: 36,
            child: _SquareBtn(
              onTap: () {
                final vc = ref.read(voiceProvider.notifier);
                vc.stopSpeaking();
                vc.resetConversation();
                setState(_clearSearch);
              },
              child: const Icon(Icons.more_horiz_rounded, color: _ink, size: 40),
            ),
          ),
          // Status pill (pastki markaz) — to'lqin ikonkasi + holat matni
          Positioned(
            bottom: 64,
            left: 150,
            right: 150,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(46),
                  boxShadow: const [BoxShadow(color: Color(0x2410266B), offset: Offset(0, 6), blurRadius: 22)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq_rounded,
                        color: v.recording ? const Color(0xFFE5484D) : _indigo, size: 36),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(_statusText(v, t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: _ink)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isWarmup)
            Positioned.fill(
              child: IgnorePointer(child: _WarmupOverlay(progress: _warmupProgress, dark: false)),
            ),
        ],
      ),
    );
  }

  /// Salomlashuv bloki (mockup): sarlavha kartasi + savol kartasi.
  Widget _greeting(Map<String, dynamic> t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x1229306B), offset: Offset(0, 6), blurRadius: 20)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t['aiHello'], style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 10),
              Text(t['aiIntro'],
                  style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w500, color: _slate, height: 1.35)),
              const SizedBox(height: 18),
              Container(
                width: 64,
                height: 7,
                decoration: BoxDecoration(
                  color: _indigo.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x0F29306B), offset: Offset(0, 5), blurRadius: 16)],
          ),
          child: Text(t['aiAsk'],
              style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w600, color: _ink, height: 1.4)),
        ),
      ],
    );
  }

  /// Javob matni (olov ikonkasi + indigo raqamlar) — salomlashuv o'rnida chiqadi.
  Widget _answerHead(String text) {
    final fs = text.length > 220 ? 27.0 : 31.0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 430),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x1229306B), offset: Offset(0, 6), blurRadius: 20)],
        ),
        child: SingleChildScrollView(
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
      ),
    );
  }

  /// Xizmat kartasi (mockup): ikonka-plitka + nom + rangli son-chip + chevron.
  Widget _svcRow(_Svc s) {
    return GestureDetector(
      onTap: () => _ask(s.query),
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x0F29306B), offset: Offset(0, 5), blurRadius: 16)],
        ),
        child: Row(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: s.iconBg, borderRadius: BorderRadius.circular(22)),
              child: Icon(s.icon, color: s.color, size: 44),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Text(s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 33, fontWeight: FontWeight.w700, color: _ink)),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: s.iconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(s.count == null ? '…' : fmt(s.count!),
                  style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800, color: s.color)),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFC2C8E4), size: 40),
          ],
        ),
      ),
    );
  }

  /// Javob jadvali qatori — xizmat kartalari bilan bir xil uslub.
  Widget _tableRow(List<dynamic> r) {
    final label = '${r.isNotEmpty ? r[0] : ''}';
    final b = _badge(label);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x0F29306B), offset: Offset(0, 4), blurRadius: 14)],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: b.$2, borderRadius: BorderRadius.circular(16)),
            child: Icon(b.$1, color: b.$3, size: 34),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w600, color: _ink)),
          ),
          const SizedBox(width: 14),
          Text(r.length > 1 ? _cell(r[1]) : '',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _indigo)),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFC2C8E4), size: 36),
        ],
      ),
    );
  }
}

class _Svc {
  const _Svc(this.icon, this.iconBg, this.color, this.label, this.count, this.query);
  final IconData icon;
  final Color iconBg;
  final Color color;
  final String label;
  final int? count;
  final String query;
}

/// Oq kvadrat tugma (orqaga / "...") — mockup uslubi.
class _SquareBtn extends StatelessWidget {
  const _SquareBtn({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x1F10266B), offset: Offset(0, 6), blurRadius: 18)],
        ),
        child: child,
      ),
    );
  }
}

/// Yuqori-o'ng dumaloq avatar: jim = rasm, gapirganda = lab-sinx video SHU doirada,
/// pastki-o'ngda yashil onlayn nuqta (mockup 1:1).
class _AvatarCircle extends ConsumerWidget {
  const _AvatarCircle({required this.url, required this.ap, required this.speaking, required this.fallbackHasImg});
  final String? url;
  final AvatarPlayerState ap;
  final bool speaking;
  final bool fallbackHasImg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const d = 252.0;
    final vc = ap.controller;
    final hasVideo = vc != null && vc.value.isInitialized;
    return SizedBox(
      width: d + 8,
      height: d + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFDDE3F5),
              border: Border.all(color: speaking ? const Color(0xFF5457F5) : Colors.white, width: 6),
              boxShadow: speaking
                  ? [const BoxShadow(color: Color(0x595457F5), blurRadius: 36, spreadRadius: 4)]
                  : [const BoxShadow(color: Color(0x2410266B), offset: Offset(0, 8), blurRadius: 24)],
            ),
            clipBehavior: Clip.antiAlias,
            child: hasVideo
                ? FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: vc.value.size.width <= 0 ? 720 : vc.value.size.width,
                      height: vc.value.size.height <= 0 ? 1280 : vc.value.size.height,
                      child: WinVideoPlayer(vc),
                    ),
                  )
                : (url != null
                    ? Image.network(url!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Center(child: kIcon('ai', size: 110, color: const Color(0xFF8A93BF))))
                    : Center(child: kIcon('ai', size: 110, color: const Color(0xFF8A93BF)))),
          ),
          // Onlayn nuqta
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 6),
              ),
            ),
          ),
        ],
      ),
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
