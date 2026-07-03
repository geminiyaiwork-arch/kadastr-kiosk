import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
    final url = enabled ? '${Env.apiBase}/avatar/file?${avatar!.imageQuery}' : null;  // /api/v1 bilan (resolveMedia 404 berardi); video bo'lsa idle jpg
    // JONLI avatar videosini tayyorlash — REAKTIV (konfig kechroq kelsa ham boshlanadi;
    // ensureIdle ichida bir-marta-yuklash guardi bor, keshда saqlanadi)
    if (avatar != null && enabled) {
      ref.read(avatarPlayerProvider.notifier).ensureIdle(avatar);
    }
    final hasData = v.answer.isNotEmpty;

    return Container(
      color: T.aiDark,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        // Avatar: javob yo'q — TO'LIQ ekran; javob bor — yuqori-o'ng burchakda DUMALOQ.
        const corner = 210.0;
        final rect = hasData
            ? Rect.fromLTWH(w - corner - 30, 30, corner, corner)
            : Rect.fromLTWH(0, 0, w, h);
        return Stack(
          children: [
            // dumaloq/to'liq avatar — bitta widget, o'lchami-joyi ANIMATSIYA bilan o'zgaradi
            AnimatedPositioned(
              duration: _fx,
              curve: _fxCurve,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: AnimatedContainer(
                duration: _fx,
                curve: _fxCurve,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(hasData ? corner / 2 : 0),
                  border: hasData ? Border.all(color: v.speaking ? T.blue : Colors.white24, width: 5) : null,
                  boxShadow: v.speaking
                      ? [const BoxShadow(color: Color(0x732F6FE3), blurRadius: 46, spreadRadius: 6)]
                      : (hasData ? [const BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))] : null),
                ),
                child: Builder(builder: (context) {
                  // JONLI avatar: video tayyor bo'lsa — media_kit Video (bo'shda loop:
                  // kiprik/harakat; gapirganda lab-sinxron klip). Aks holda rasm-fallback.
                  final apReady = ref.watch(avatarPlayerProvider).ready;
                  final vctl = ref.read(avatarPlayerProvider.notifier).controller;
                  if (enabled && apReady && vctl != null) {
                    return Video(controller: vctl, controls: NoVideoControls, fit: BoxFit.cover);
                  }
                  return (enabled && url != null)
                      ? Image.network(url, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(child: kIcon('ai', size: hasData ? 100 : 220, color: Colors.white)))
                      : Center(child: kIcon('ai', size: hasData ? 100 : 220, color: Colors.white));
                }),
              ),
            ),
            // JAVOB maydoni — matn + jadval KATTA ekranda (pastdan suzib chiqadi)
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
                      color: v.recording ? const Color(0xFFE5484D) : T.blue,
                      boxShadow: [
                        BoxShadow(
                          color: v.recording ? const Color(0x66E5484D) : const Color(0x662F6FE3),
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

/// Javob: matn karta + (bo'lsa) KATTA jadval — uzun bo'lsa ichida aylanadi (scroll).
class _AnswerView extends StatelessWidget {
  const _AnswerView({required this.text, required this.table});
  final String text;
  final List<List<dynamic>>? table;

  String _cell(dynamic v) {
    final s = '$v';
    final n = num.tryParse(s.replaceAll(RegExp(r'[\s ]'), ''));
    return n != null ? fmt(n) : s;   // raqam -> 1 812 ko'rinishida; matn ("250 000 so'm") o'z holicha
  }

  @override
  Widget build(BuildContext context) {
    final rows = table ?? const <List<dynamic>>[];
    final hasTable = rows.isNotEmpty;
    // Ba'zi javoblar jadvalni SARLAVHASIZ yuboradi (masalan noqonuniy-yerlar ro'yxati).
    // Sarlavha deb faqat 2-katagi RAQAM BO'LMAGAN birinchi qator olinadi ("Nomi|Soni").
    final headed = rows.isNotEmpty &&
        rows[0].length > 1 &&
        num.tryParse('${rows[0][1]}'.replaceAll(RegExp(r'[\s ]'), '')) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Matnli javob (ovozda o'qiladigan gap)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [BoxShadow(color: Color(0x2410266B), offset: Offset(0, 10), blurRadius: 34)],
          ),
          child: Text(text,
              style: TextStyle(
                fontSize: text.length > 220 ? 28 : 33,
                fontWeight: FontWeight.w600,
                color: T.navy,
                height: 1.42,
              )),
        ),
        if (hasTable) ...[
          const SizedBox(height: 22),
          Flexible(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [BoxShadow(color: Color(0x2410266B), offset: Offset(0, 10), blurRadius: 34)],
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // sarlavha qatori (faqat haqiqiy sarlavha bo'lsa)
                    if (headed)
                      Container(
                        color: const Color(0xFFF2F5FC),
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 26),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text('${rows[0].isNotEmpty ? rows[0][0] : ''}',
                                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: T.navy))),
                            Text(rows[0].length > 1 ? '${rows[0][1]}' : '',
                                style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: T.navy)),
                          ],
                        ),
                      ),
                    for (var i = headed ? 1 : 0; i < rows.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 26),
                        decoration: BoxDecoration(
                          color: i.isEven ? const Color(0xFFFAFBFE) : Colors.white,
                          border: const Border(top: BorderSide(color: T.line)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text('${rows[i].isNotEmpty ? rows[i][0] : ''}',
                                    style: const TextStyle(fontSize: 29, color: T.muted))),
                            const SizedBox(width: 16),
                            Flexible(
                                child: Text(rows[i].length > 1 ? _cell(rows[i][1]) : '',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: T.navy))),
                          ],
                        ),
                      ),
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
