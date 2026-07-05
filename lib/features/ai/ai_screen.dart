import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/env.dart';
import '../../core/i18n/strings.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final t = I18N[ref.read(localeProvider)]!;
      final vc = ref.read(voiceProvider.notifier);
      vc.resetConversation(); // eski javob/jadval tozalanadi — avatar to'liq ekranda salomlashadi
      vc.greet(t['aiGreet']);
    });
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
        ref.watch(avatarPlayerProvider); // video boshlanganda rebuild (Builder controllerni oladi)
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
                    // Video moduli olib tashlangan (SAC libmpv DLL'ni bloklaydi) —
                    // avatar STATIK rasm sifatida ko'rsatiladi, javob TTS ovozida.
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

/// MOCKUP uslubidagi javob: yaltiroq-belgi + raqamlari INDIGO-BOLD matn-karta,
/// har qatori RANGLI IKONKA-BELGILI jadval (Nomi | Soni), yumaloq oq kartalar.
class _AnswerView extends StatelessWidget {
  const _AnswerView({required this.text, required this.table});
  final String text;
  final List<List<dynamic>>? table;

  static const _ink = Color(0xFF232A4D);
  static const _indigo = Color(0xFF5457F5);

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

  /// Qator uchun mavzuga mos ikonka + rang (mockup: odamlar/uy/pin/bino).
  (IconData, Color, Color) _badge(String label, int i) {
    final l = label.toLowerCase();
    if (l.contains('tuman') || l.contains('shahar') || l.contains('mahalla') || l.contains('aholi')) {
      return (Icons.groups_rounded, const Color(0xFFEDE7FE), const Color(0xFF7C5CFC));
    }
    if (l.contains('mulk') || l.contains('uy') || l.contains('xonadon')) {
      return (Icons.home_rounded, const Color(0xFFE3F0FE), const Color(0xFF2E90FA));
    }
    if (l.contains('yer') || l.contains('uchastka') || l.contains('maydon')) {
      return (Icons.location_on_rounded, const Color(0xFFE2F8EC), const Color(0xFF16B364));
    }
    if (l.contains('xatlov') || l.contains('obyekt') || l.contains('bino') || l.contains('ariza')) {
      return (Icons.apartment_rounded, const Color(0xFFFEF0E1), const Color(0xFFF79009));
    }
    const cyc = [
      (Icons.groups_rounded, Color(0xFFEDE7FE), Color(0xFF7C5CFC)),
      (Icons.home_rounded, Color(0xFFE3F0FE), Color(0xFF2E90FA)),
      (Icons.location_on_rounded, Color(0xFFE2F8EC), Color(0xFF16B364)),
      (Icons.apartment_rounded, Color(0xFFFEF0E1), Color(0xFFF79009)),
    ];
    return cyc[i % cyc.length];
  }

  @override
  Widget build(BuildContext context) {
    final rows = table ?? const <List<dynamic>>[];
    final hasTable = rows.isNotEmpty;
    final headed =
        rows.isNotEmpty && rows[0].length > 1 && num.tryParse('${rows[0][1]}'.replaceAll(RegExp(r'[\s\u00A0]'), '')) == null;
    final fs = text.length > 220 ? 27.0 : 31.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // MATN-KARTA: yaltiroq-belgi + raqamlari ajratilgan matn
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: const Color(0xFFE9EAFB),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x1A29306B), offset: Offset(0, 8), blurRadius: 26)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: const Color(0xFFDCDDFB), borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.auto_awesome, color: _indigo, size: 34),
              ),
              const SizedBox(width: 22),
              Expanded(child: RichText(text: TextSpan(children: _rich(text, fs)))),
            ],
          ),
        ),
        if (hasTable) ...[
          const SizedBox(height: 22),
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
                              child: Text(headed ? '${rows[0][0]}' : 'Nomi',
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink))),
                          Text(headed && rows[0].length > 1 ? '${rows[0][1]}' : 'Soni',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink)),
                        ],
                      ),
                    ),
                    for (var i = headed ? 1 : 0; i < rows.length; i++)
                      Builder(builder: (context) {
                        final label = '${rows[i].isNotEmpty ? rows[i][0] : ''}';
                        final b = _badge(label, i);
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 26),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEDEFF9)))),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(color: b.$2, borderRadius: BorderRadius.circular(16)),
                                child: Icon(b.$1, color: b.$3, size: 32),
                              ),
                              const SizedBox(width: 22),
                              Expanded(
                                  child: Text(label,
                                      style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w600, color: _ink))),
                              const SizedBox(width: 16),
                              Flexible(
                                  child: Text(rows[i].length > 1 ? _cell(rows[i][1]) : '',
                                      textAlign: TextAlign.right,
                                      style:
                                          const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _indigo))),
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
