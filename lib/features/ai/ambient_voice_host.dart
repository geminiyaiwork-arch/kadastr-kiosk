import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../router.dart';
import 'voice_controller.dart';

/// Starts the single always-on voice listener on the first user interaction,
/// and keeps its language in sync. The listener wakes on "KAI" from any page
/// (except /appeal) and is direct on /ai.
class AmbientVoiceHost extends ConsumerStatefulWidget {
  const AmbientVoiceHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AmbientVoiceHost> createState() => _AmbientVoiceHostState();
}

class _AmbientVoiceHostState extends ConsumerState<AmbientVoiceHost> {
  bool _started = false;

  void _startOnce() {
    if (_started) return;
    _started = true;
    final notifier = ref.read(voiceProvider.notifier);
    notifier.startAmbient(
      lang: ref.read(localeProvider),
      onAiPage: () => ref.read(currentRouteProvider) == '/ai',
      canListen: () => ref.read(currentRouteProvider) != '/appeal',
      navToAi: () => ref.read(routerProvider).go('/ai'),
    );
  }

  @override
  Widget build(BuildContext context) {
    // keep the recogniser language in sync with the UI language
    ref.listen(localeProvider, (_, lang) => ref.read(voiceProvider.notifier).setLang(lang));
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _startOnce(),
      child: widget.child,
    );
  }
}
