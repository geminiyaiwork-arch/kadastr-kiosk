import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/core/network/api_client.dart';
import 'package:kadastr_kiosk/core/network/models.dart';
import 'package:kadastr_kiosk/core/network/repository.dart';
import 'package:kadastr_kiosk/features/ai/voice_controller.dart';

import '../tool/mock_voice_server.dart';
import 'speech_queue_test.dart' show FakeClipPlayer;

Future<void> _until(bool Function() cond, {int ms = 5000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) throw StateError('condition not met in ${ms}ms');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// VoiceController "yelimi": navbat egaligi (turn), bekor qilish, fallback eslab qolish,
/// til almashishi, ovoz bilan kirish — soxta o'ynatuvchi + lokal mock server bilan.
void main() {
  late MockVoiceServer server;
  late ProviderContainer c;
  late FakeClipPlayer player;
  late VoiceController vc;

  setUp(() async {
    server = await MockVoiceServer.start();
    player = FakeClipPlayer(clipMs: 60);
    final dio = Dio(BaseOptions(baseUrl: '${server.origin}/api/v1'));
    c = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(dio),
      avatarProvider.overrideWith((ref) async => const AvatarConfig()),
      voiceProvider.overrideWith((ref) => VoiceController(ref, player: player)),
    ]);
    await c.read(avatarProvider.future);
    vc = c.read(voiceProvider.notifier);
  });

  tearDown(() async {
    c.dispose();
    await server.close();
  });

  test('typed question: progressive text, all sentences in order, table, ends idle', () async {
    final answers = <String>[];
    c.listen(voiceProvider.select((s) => s.answer), (_, n) => answers.add(n));
    await vc.askAI('auksion yerlar nechta');
    expect(player.played, [0, 1, 2]);
    expect(player.maxConcurrent, 1);
    final st = c.read(voiceProvider);
    expect(st.answer, startsWith('Auksion yerlar: jami 19 649 ta. Eng'));
    expect(st.table, isNotNull);
    expect(st.speaking, isFalse);
    expect(vc.busy, isFalse);
    expect(vc.inQuestion, isFalse);
    expect(answers.first, 'Auksion yerlar: jami 19 649 ta.'); // shown before the rest arrived
    expect(server.streamBodies.single['voice'], 'madina');
  });

  test('a new question cancels the old one: no stale audio, mic stays owned by the new turn', () async {
    final f1 = vc.askAI('birinchi savol');
    await _until(() => player.played.isNotEmpty);
    final f2 = vc.askAI('ikkinchi savol');
    await f1.timeout(const Duration(seconds: 2));
    expect(vc.busy, isTrue, reason: 'old answer must not release the mic of the new one');
    await f2;
    expect(player.played, [0, 0, 1, 2]);
    expect(player.maxConcurrent, 1);
    expect(vc.busy, isFalse);
    expect(server.streamAborted, greaterThanOrEqualTo(1));
  });

  test('page change (stopSpeaking) mid-answer: stream closed, nothing plays later', () async {
    final f = vc.askAI('x');
    await _until(() => player.played.isNotEmpty);
    await vc.stopSpeaking();
    await f.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(player.played, [0]);
    expect(c.read(voiceProvider).speaking, isFalse);
    expect(vc.busy, isFalse);
    expect(vc.inQuestion, isFalse);
    expect(server.streamAborted, 1);
  });

  test('stopSpeaking while still waiting for the server → no audio ever plays', () async {
    server.mode = 'slow';
    final f = vc.askAI('x');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await vc.stopSpeaking();
    await f.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(player.played, isEmpty);
    expect(c.read(voiceProvider).phase, isNot(VoicePhase.thinking));
  });

  test('404 is remembered for the session (no extra round-trip on later turns)', () async {
    server.mode = '404';
    await vc.askAI('a');
    await vc.askAI('b');
    expect(server.hits['/api/v1/ai/chat-stream'], 1);
    expect(server.hits['/api/v1/ai/chat'], 2);
    expect(player.played, [0, 1, 0, 1]);
    expect(c.read(voiceProvider).table, isNotNull);
  });

  test('empty answer → apology shown and spoken', () async {
    server.mode = 'empty';
    await vc.askAI('x');
    expect(c.read(voiceProvider).answer, startsWith('Kechirasiz, hozir javob bera olmadim.'));
    expect(player.played, [0, 1]);
    expect(vc.busy, isFalse);
  });

  test('language switch mid-answer stops the old-language answer', () async {
    final f = vc.askAI('x');
    await _until(() => player.played.isNotEmpty);
    vc.setLang('ru');
    await f.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(player.played, [0]);
  });

  test('greet is ignored while a question is being answered', () async {
    final f = vc.askAI('x');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await vc.greet('Assalomu alaykum!');
    await f;
    expect(player.played, [0, 1, 2]);
    expect(server.hits['/api/v1/tts/synthesize'], isNull);
  });

  test('remote/voice question from another page: navigates once, flags voice entry', () async {
    var navs = 0;
    vc.onAiPage = () => false;
    vc.navToAi = () => navs++;
    await vc.handleRemoteText('auksion yerlar nechta');
    expect(navs, 1);
    expect(vc.consumeVoiceEntry(), isTrue);
    expect(vc.consumeVoiceEntry(), isFalse);
    expect(player.played, [0, 1, 2]);
  });
}
