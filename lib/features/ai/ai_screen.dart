import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/repository.dart';
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
      ref.read(voiceProvider.notifier).greet(t['aiGreet']);
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

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final v = ref.watch(voiceProvider);
    final avatar = ref.watch(avatarProvider).valueOrNull;
    final enabled = avatar?.enabled ?? false;
    final url = enabled ? resolveMedia('/avatar/file?${avatar!.imageQuery}') : null;  // video bo'lsa idle jpg (36MB mp4 render buzadi)
    final hasData = v.answer.isNotEmpty;

    return Container(
      color: T.aiDark,
      child: Stack(
        children: [
          // full-bleed avatar (small when data is shown)
          if (!hasData)
            Positioned.fill(child: _Avatar(speaking: v.speaking, enabled: enabled, url: url, full: true)),
          if (hasData)
            Positioned(
              top: 90,
              left: 0,
              right: 0,
              child: Center(child: _Avatar(speaking: v.speaking, enabled: enabled, url: url, full: false)),
            ),
          if (hasData)
            Positioned(
              top: 360,
              left: 0,
              right: 0,
              child: Center(child: _DataCard(text: v.answer, table: v.table)),
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
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.speaking, required this.enabled, required this.url, required this.full});
  final bool speaking, enabled, full;
  final String? url;
  @override
  Widget build(BuildContext context) {
    if (enabled && url != null && full) {
      // full-bleed talking head
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: T.aiDark)),
          if (speaking)
            const DecoratedBox(
              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x732F6FE3), blurRadius: 80, spreadRadius: 20)]),
            ),
        ],
      );
    }
    final size = full ? 460.0 : 240.0;
    return AnimatedScale(
      scale: speaking && !enabled ? 1.04 : 1,
      duration: const Duration(milliseconds: 380),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: speaking ? T.blue : Colors.white24, width: 6),
          boxShadow: speaking ? [const BoxShadow(color: Color(0x732F6FE3), blurRadius: 50, spreadRadius: 6)] : null,
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: enabled && url != null
            ? Image.network(url!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, __, ___) => kIcon('ai', size: size * 0.5, color: Colors.white))
            : kIcon('ai', size: size * 0.5, color: Colors.white),
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.text, required this.table});
  final String text;
  final List<List<dynamic>>? table;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1000),
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x2410266B), offset: Offset(0, 10), blurRadius: 34)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: T.navy, height: 1.45)),
          if (table != null && table!.isNotEmpty) ...[
            const SizedBox(height: 22),
            for (var i = 0; i < table!.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                decoration: BoxDecoration(
                  border: i == table!.length - 1 ? null : const Border(bottom: BorderSide(color: T.line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${table![i].isNotEmpty ? table![i][0] : ''}', style: const TextStyle(fontSize: 30, color: T.muted)),
                    Text(table![i].length > 1 ? fmt(num.tryParse('${table![i][1]}') ?? 0) : '',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: T.navy)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
