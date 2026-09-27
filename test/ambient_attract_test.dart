import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/core/network/api_client.dart';
import 'package:kadastr_kiosk/core/network/models.dart';
import 'package:kadastr_kiosk/core/network/repository.dart';
import 'package:kadastr_kiosk/features/ai/attract_wake_guard.dart';
import 'package:kadastr_kiosk/features/ai/voice_controller.dart';
import 'package:kadastr_kiosk/features/ai/wav_tools.dart';
import 'package:record/record.dart';

import '../tool/mock_voice_server.dart';
import 'speech_queue_test.dart' show FakeClipPlayer;

/// Plaginsiz mikrofon: ruxsat/ochilish xatolarini va skriptlangan gaplarni taqlid qiladi.
/// Gap: navbatdagi [speak] chaqiruvi joriy (yoki keyingi) yozuvga 100 ms dan keyin
/// [ms] davomida -20 dBFS "nutq" beradi; stop() haqiqiy WAV (sinus) yozadi.
class FakeRecorder extends AudioRecorder {
  FakeRecorder({this.permissionFailures = 0, this.startFailures = 0});
  int permissionFailures;
  int startFailures;
  final permissionCallTimes = <DateTime>[];
  final startCallTimes = <DateTime>[];
  final _pending = <int>[];
  bool _recording = false;
  String? _path;
  Stopwatch? _sw;
  int? _speechStart, _speechMs;

  void speak({int ms = 900}) => _pending.add(ms);
  int get pendingUtterances => _pending.length;

  @override
  Future<bool> hasPermission() async {
    permissionCallTimes.add(DateTime.now());
    if (permissionFailures > 0) {
      permissionFailures--;
      return false;
    }
    return true;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCallTimes.add(DateTime.now());
    if (startFailures > 0) {
      startFailures--;
      throw StateError('device not ready');
    }
    _recording = true;
    _path = path;
    _sw = Stopwatch()..start();
    _speechStart = null;
    _speechMs = null;
  }

  @override
  Future<Amplitude> getAmplitude() async {
    final el = _sw?.elapsedMilliseconds ?? 0;
    if (_recording && _speechStart == null && _pending.isNotEmpty) {
      _speechMs = _pending.removeAt(0);
      _speechStart = el + 100;
    }
    final s = _speechStart;
    final speaking = s != null && el >= s && el <= s + _speechMs!;
    return Amplitude(current: speaking ? -20 : -60, max: -20);
  }

  @override
  Future<bool> isRecording() async => _recording;

  @override
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    final total = _sw!.elapsedMilliseconds + 50;
    const rate = 16000;
    final n = rate * total ~/ 1000;
    final pcm = Uint8List(n * 2);
    final bd = ByteData.sublistView(pcm);
    final s0 = _speechStart, len = _speechMs;
    if (s0 != null && len != null) {
      final a = rate * s0 ~/ 1000, b = min(n, rate * (s0 + len) ~/ 1000);
      for (var i = a; i < b; i++) {
        bd.setInt16(i * 2, (0.3 * 32767 * sin(i / 6)).round(), Endian.little);
      }
    }
    File(_path!).writeAsBytesSync(buildWav(pcm, sampleRate: rate));
    return _path;
  }

  @override
  Future<void> dispose() async {}
}

Future<void> _until(bool Function() cond, {int ms = 8000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) throw StateError('condition not met in ${ms}ms');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('AttractWakeGuard', () {
    test('3 unconfirmed wakes, each ≤10 min apart → blocked until touch', () {
      var now = DateTime(2026, 9, 27, 10);
      final g = AttractWakeGuard(clock: () => now);
      expect(g.onWake(), isTrue);
      now = now.add(const Duration(seconds: 331)); // zastavka qaytdi
      expect(g.onWake(), isTrue);
      now = now.add(const Duration(seconds: 331));
      expect(g.onWake(), isTrue); // 3rd is handled, then listening is switched off
      expect(g.blocked, isTrue);
      now = now.add(const Duration(minutes: 20));
      expect(g.onWake(), isFalse); // still blocked (auto-expiry is 30 min)
      g.onTouch();
      expect(g.blocked, isFalse);
      expect(g.onWake(), isTrue);
    });

    test('block auto-expires after 30 min even without a touch', () {
      var now = DateTime(2026, 9, 27, 10);
      final g = AttractWakeGuard(clock: () => now);
      for (var i = 0; i < 3; i++) {
        if (i > 0) now = now.add(const Duration(minutes: 5));
        g.onWake();
      }
      expect(g.blocked, isTrue); // blocked at the 3rd wake
      now = now.add(const Duration(minutes: 29));
      expect(g.blocked, isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(g.blocked, isFalse);
      expect(g.streak, 0);
    });

    test('real follow-up speech or a >10 min gap resets the streak', () {
      var now = DateTime(2026, 9, 27, 10);
      final g = AttractWakeGuard(clock: () => now);
      g.onWake();
      g.onWake();
      g.onRealSpeech();
      g.onWake();
      g.onWake();
      expect(g.blocked, isFalse);
      now = now.add(const Duration(minutes: 11));
      g.onWake();
      expect(g.streak, 1);
      expect(g.blocked, isFalse);
    });
  });

  group('auto-start + retry', () {
    late MockVoiceServer server;
    late ProviderContainer c;
    setUp(() async => server = await MockVoiceServer.start());
    tearDown(() async {
      c.dispose();
      await server.close();
    });

    VoiceController make(FakeRecorder rec) {
      c = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: '${server.origin}/api/v1'))),
        avatarProvider.overrideWith((ref) async => const AvatarConfig()),
        voiceProvider.overrideWith((ref) => VoiceController(ref,
            player: FakeClipPlayer(),
            recorder: rec,
            retryBackoff: const [
              Duration(milliseconds: 40),
              Duration(milliseconds: 100),
              Duration(milliseconds: 200),
              Duration(milliseconds: 400),
            ])),
      ]);
      return c.read(voiceProvider.notifier);
    }

    Future<void> start(VoiceController vc) => vc.startAmbient(
        lang: 'uz', onAiPage: () => false, canListen: () => true, navToAi: () {}, navTo: (_) {});

    test('mic not ready at boot → retried with growing backoff, then starts', () async {
      final rec = FakeRecorder(permissionFailures: 5);
      final vc = make(rec);
      await start(vc);
      expect(vc.isOn, isFalse);
      expect(c.read(voiceProvider).error, 'mic');
      await _until(() => vc.isOn, ms: 5000);
      expect(rec.permissionCallTimes.length, 6);
      final gaps = [
        for (var i = 1; i < rec.permissionCallTimes.length; i++)
          rec.permissionCallTimes[i].difference(rec.permissionCallTimes[i - 1]).inMilliseconds
      ];
      // 40, 100, 200, 400, 400 (last one repeats)
      for (final (i, min) in [(0, 35), (1, 90), (2, 180), (3, 370), (4, 370)]) {
        expect(gaps[i], greaterThanOrEqualTo(min), reason: 'gap $i = ${gaps[i]} ms');
      }
      expect(c.read(voiceProvider).error, isNull);
      expect(c.read(voiceProvider).phase, VoicePhase.listening);
      await vc.stop();
    });

    test('a touch while a retry is pending tries again immediately', () async {
      final rec = FakeRecorder(permissionFailures: 1);
      final vc = make(rec);
      await start(vc);
      expect(vc.isOn, isFalse);
      await start(vc); // touch backup
      expect(vc.isOn, isTrue);
      expect(rec.permissionCallTimes.length, 2);
      await vc.stop();
    });

    test('recorder fails to open → backoff instead of a tight retry loop', () async {
      final rec = FakeRecorder(startFailures: 3);
      final vc = make(rec);
      await start(vc);
      await _until(() => rec.startCallTimes.length >= 4, ms: 3000);
      final t = rec.startCallTimes;
      expect(t[1].difference(t[0]).inMilliseconds, greaterThanOrEqualTo(35));
      expect(t[2].difference(t[1]).inMilliseconds, greaterThanOrEqualTo(90));
      expect(t[3].difference(t[2]).inMilliseconds, greaterThanOrEqualTo(180));
      await vc.stop();
    });
  });

  group('screensaver = wake-only listening', () {
    late MockVoiceServer server;
    late ProviderContainer c;
    late FakeRecorder rec;
    late FakeClipPlayer player;
    late VoiceController vc;
    var attract = true;
    var dismissals = 0;
    var navs = 0;
    var route = '/';

    setUp(() async {
      server = await MockVoiceServer.start();
      rec = FakeRecorder();
      player = FakeClipPlayer(clipMs: 40);
      attract = true;
      dismissals = 0;
      navs = 0;
      route = '/';
      c = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: '${server.origin}/api/v1'))),
        avatarProvider.overrideWith((ref) async => const AvatarConfig()),
        voiceProvider.overrideWith((ref) => VoiceController(ref,
            player: player, recorder: rec, attractPause: const Duration(milliseconds: 1500))),
      ]);
      await c.read(avatarProvider.future);
      vc = c.read(voiceProvider.notifier);
      await vc.startAmbient(
        lang: 'uz',
        onAiPage: () => route == '/ai',
        canListen: () => true,
        wakeOnly: () => attract,
        dismissAttract: () {
          attract = false;
          dismissals++;
        },
        navToAi: () {
          navs++;
          route = '/ai';
        },
        navTo: (r) => route = r,
      );
    });

    tearDown(() async {
      await vc.stop();
      c.dispose();
      await server.close();
    });

    int stt() => server.hits['/api/v1/stt'] ?? 0;

    const maxClip = 44 + 16000 * 2 * 2500 ~/ 1000; // 2.5 s PCM16 mono + header

    test('screensaver clips are ≤2.5 s and sent with mode=wake; long wake+question re-sent once in full',
        () async {
      server.sttScript.addAll(['Alomat auksion', 'Alomat, auksion yerlar nechta']);
      rec.speak(ms: 3000);
      await _until(() => player.played.length == 3);
      expect(server.sttRequests.length, 2);
      final (mode1, size1) = server.sttRequests[0];
      expect(mode1, 'wake');
      expect(size1, lessThanOrEqualTo(maxClip));
      final (mode2, size2) = server.sttRequests[1];
      expect(mode2, isNull); // normal mode after the wake is confirmed
      expect(size2, greaterThan(maxClip));
      expect(server.streamBodies.single['q'], 'auksion yerlar nechta');
    });

    test('duty-cycle cap: 6 screensaver clips without a wake → pause, then resume', () async {
      for (var i = 1; i <= 6; i++) {
        server.sttScript.add('musiqa va reklama $i');
        rec.speak(ms: 500);
        await _until(() => stt() == i);
      }
      await _until(() => vc.attractPaused, ms: 2000);
      expect(server.sttRequests.every((r) => r.$1 == 'wake' && r.$2 <= maxClip), isTrue);
      server.sttScript.add('Alomat');
      rec.speak(ms: 500);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(stt(), 6, reason: 'no clips are sent while paused');
      await _until(() => dismissals == 1, ms: 6000); // resumes after the (test) 1.5 s pause
      expect(vc.attractPaused, isFalse);
    });

    test('a touch cancels the duty-cycle pause', () async {
      for (var i = 1; i <= 6; i++) {
        server.sttScript.add('shovqin $i');
        rec.speak(ms: 400);
        await _until(() => stt() == i);
      }
      await _until(() => vc.attractPaused, ms: 2000);
      vc.noteTouch();
      expect(vc.attractPaused, isFalse);
    });

    test('speech without the wake word (or wake word not first) is ignored', () async {
      server.sttScript.addAll(['Bugun havo juda yaxshi', 'Salom Alomat qalaysan']);
      rec.speak();
      await _until(() => stt() == 1);
      rec.speak();
      await _until(() => stt() == 2);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(attract, isTrue);
      expect(dismissals, 0);
      expect(navs, 0);
      expect(server.hits['/api/v1/ai/chat-stream'], isNull);
      expect(server.hits['/api/v1/ai/heard'], isNull); // video audio is not logged
      expect(player.played, isEmpty);
    });

    test('"Alomat, <question>" → screensaver dismissed, AI page, answered directly', () async {
      server.sttScript.add('Alomat, auksion yerlar nechta');
      rec.speak(ms: 1500);
      await _until(() => player.played.length == 3);
      expect(dismissals, 1);
      expect(attract, isFalse);
      expect(navs, 1);
      expect(vc.consumeVoiceEntry(), isTrue);
      expect(server.streamBodies.single['q'], 'auksion yerlar nechta');
      expect(player.played, [0, 1, 2]);
      // a real question in the wake utterance that got a meaningful answer confirms the wake
      await _until(() => !vc.busy);
      await _until(() => vc.attractGuard.streak == 0, ms: 1000);
    });

    test('screensaver utterance hitting the 6 s cap is still checked (first 2.5 s, mode=wake)', () async {
      server.sttScript.add('Alomat');
      rec.speak(ms: 7000);
      await _until(() => dismissals == 1, ms: 12000);
      final (mode, size) = server.sttRequests.first;
      expect(mode, 'wake');
      expect(size, lessThanOrEqualTo(maxClip));
    });

    test('bare "Alomat" → dismissed + cached "Labbay! Eshitaman." + follow-up without the name', () async {
      server.sttScript.addAll(['Alomat', 'auksion yerlar nechta']);
      rec.speak(ms: 600);
      await _until(() => player.played.length == 1);
      expect(dismissals, 1);
      expect(navs, 1);
      expect(vc.attractGuard.streak, 1);
      // follow-up (screensaver is off now) inside the 15 s window, no name needed
      rec.speak();
      await _until(() => player.played.length == 4);
      expect(server.streamBodies.single['q'], 'auksion yerlar nechta');
      expect(vc.attractGuard.streak, 0); // real follow-up speech confirmed the wake
    });

    test('self-wake guard: 3 unconfirmed screensaver wakes → listening off until a touch', () async {
      for (var i = 1; i <= 3; i++) {
        attract = true; // zastavka qaytdi
        route = '/';
        server.sttScript.add('Alomat');
        rec.speak(ms: 600);
        await _until(() => dismissals == i);
        await _until(() => !vc.busy);
      }
      expect(vc.attractGuard.blocked, isTrue);
      attract = true;
      route = '/';
      final sttBefore = stt();
      server.sttScript.add('Alomat');
      rec.speak(ms: 600);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(stt(), sttBefore, reason: 'mic is not even opened in blocked screensaver mode');
      expect(dismissals, 3);

      vc.noteTouch(); // someone touched the screen
      expect(vc.attractGuard.blocked, isFalse);
      await _until(() => dismissals == 4);
    });
  });
}
