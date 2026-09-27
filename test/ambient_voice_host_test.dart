import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/features/ai/ambient_voice_host.dart';
import 'package:kadastr_kiosk/features/ai/voice_controller.dart';

import 'ambient_attract_test.dart' show FakeRecorder;
import 'speech_queue_test.dart' show FakeClipPlayer;

// Alohida fayl: testWidgets Flutter test-binding'ini o'rnatadi va u fayldagi BARCHA
// HTTP so'rovlarni 400 bilan soxtalashtiradi (mock-server testlari bilan birga bo'lmasin).

class _SpyVoice extends VoiceController {
  _SpyVoice(super.ref) : super(player: FakeClipPlayer(), recorder: FakeRecorder());
  int starts = 0;
  int touches = 0;
  @override
  bool get isOn => starts > 0;
  @override
  Future<void> startAmbient({
    required String lang,
    required bool Function() onAiPage,
    required bool Function() canListen,
    required void Function() navToAi,
    void Function(String route)? navTo,
    bool Function()? wakeOnly,
    void Function()? dismissAttract,
  }) async =>
      starts++;
  @override
  void noteTouch() => touches++;
}

void main() {
  testWidgets('AmbientVoiceHost starts listening ~2 s after the first frame, touch is a backup', (tester) async {
    _SpyVoice? spy;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        voiceProvider.overrideWith((ref) => spy = _SpyVoice(ref)),
      ],
      child: const MaterialApp(home: AmbientVoiceHost(child: SizedBox.expand())),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(spy?.starts ?? 0, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(spy!.starts, 1);
    await tester.tap(find.byType(SizedBox));
    expect(spy!.touches, 1);
    expect(spy!.starts, 1); // already on — touch does not restart
  });

}
