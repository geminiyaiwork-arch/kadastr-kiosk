import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/features/ai/answer_session.dart';

import '../tool/mock_voice_server.dart';
import 'speech_queue_test.dart' show FakeClipPlayer;

/// Haqiqiy dio + haqiqiy HTTP (localhost mock) + soxta o'ynatuvchi: NDJSON parser,
/// navbat tartibi, filler, fallback (404/xato) va bekor qilish uchi-uchigacha.
void main() {
  late MockVoiceServer server;
  late Dio dio;

  setUp(() async {
    server = await MockVoiceServer.start();
    dio = Dio(BaseOptions(baseUrl: '${server.origin}/api/v1'));
  });
  tearDown(() async {
    dio.close(force: true);
    await server.close();
  });

  AnswerSession session(
    FakeClipPlayer player, {
    String mode = 'ok',
    bool useStream = true,
    void Function()? onUnsupported,
    List<String>? texts,
    List<int>? startedAt,
    Stopwatch? sw,
    int fillerAfterMs = 1100,
    Duration idle = const Duration(seconds: 12),
  }) {
    server.mode = mode;
    return AnswerSession(
      dio: dio,
      player: player,
      q: 'auksion yerlar nechta',
      lang: 'uz',
      voice: 'madina',
      useStream: useStream,
      onStreamUnsupported: onUnsupported,
      fetchTts: (text) async {
        final r = await dio.get<List<int>>('/tts/synthesize',
            queryParameters: {'text': text, 'voice': 'madina', 'lang': 'uz'},
            options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data!);
      },
      pickFiller: () => ('Bir soniya.', MockVoiceServer.fakeMp3('filler')),
      fillerAfter: Duration(milliseconds: fillerAfterMs),
      streamIdleTimeout: idle,
      onText: (t, {required complete, table, persona = false}) => texts?.add('${complete ? 'FULL' : 'PART'}:$t'),
      onClipStart: (c) => startedAt?.add(sw?.elapsedMilliseconds ?? 0),
    );
  }

  test('stream: first sentence plays on arrival, order kept, text progressive, table from done', () async {
    final p = FakeClipPlayer(clipMs: 30);
    final texts = <String>[];
    final started = <int>[];
    final sw = Stopwatch()..start();
    final s = session(p, texts: texts, startedAt: started, sw: sw);
    final res = await s.run();
    expect(res.path, 'stream');
    expect(res.cancelled, isFalse);
    expect(p.played, [0, 1, 2]); // no filler: first say at ~350 ms < 1100 ms
    expect(started.first, lessThan(900)); // audio starts with sentence 0, not after done
    expect(texts.first, startsWith('PART:Auksion yerlar'));
    expect(texts.where((t) => t.startsWith('PART')).length, 3);
    expect(texts.last, startsWith('FULL:Auksion yerlar: jami 19 649 ta.'));
    expect(res.table, isNotNull);
    expect(res.table!.first.first, 'Qo‘rg‘ontepa tumani');
    expect(s.spokenText, contains('Batafsil ma’lumot ekranda.'));
    expect(server.hits['/api/v1/ai/chat'], isNull);
    expect(server.hits['/api/v1/tts/synthesize'], isNull); // audio came inline
    expect(server.streamBodies.single, {'q': 'auksion yerlar nechta', 'lang': 'uz', 'voice': 'madina'});
  });

  test('stream split byte-by-byte (UTF-8 boundaries over a real socket)', () async {
    final p = FakeClipPlayer(clipMs: 10);
    final texts = <String>[];
    final res = await session(p, mode: 'split', texts: texts).run();
    expect(res.path, 'stream');
    expect(p.played, [0, 1, 2]);
    expect(texts.last, contains('Qo‘rg‘ontepa'));
  });

  test('slow first sentence → filler first, real answer right after it', () async {
    final p = FakeClipPlayer(clipMs: 100);
    final s = session(p, mode: 'slow', fillerAfterMs: 600);
    final res = await s.run();
    expect(res.path, 'stream');
    expect(p.played, [-1, 0, 1, 2]);
    expect(s.spokenText, startsWith('Bir soniya.'));
  });

  test('audio:null → client fetches /tts/synthesize per sentence, order kept', () async {
    final p = FakeClipPlayer(clipMs: 10);
    final res = await session(p, mode: 'noaudio').run();
    expect(res.path, 'stream');
    expect(p.played, [0, 1, 2]);
    expect(server.hits['/api/v1/tts/synthesize'], 3);
  });

  test('404 → fallback to /ai/chat + TTS, remembered for the session', () async {
    final p = FakeClipPlayer(clipMs: 10);
    var unsupported = false;
    final texts = <String>[];
    final res = await session(p, mode: '404', onUnsupported: () => unsupported = true, texts: texts).run();
    expect(res.path, 'fallback-unsupported');
    expect(unsupported, isTrue);
    expect(server.hits['/api/v1/ai/chat'], 1);
    expect(p.played, [0, 1]); // head + tail
    expect(texts.single, startsWith('FULL:Auksion yerlar'));
    expect(res.table, isNotNull);

    // next turn: the caller passes useStream=false → no extra round-trip
    final before = server.hits['/api/v1/ai/chat-stream'];
    final res2 = await session(FakeClipPlayer(clipMs: 10), mode: '404', useStream: false).run();
    expect(res2.path, 'fallback');
    expect(server.hits['/api/v1/ai/chat-stream'], before);
  });

  test('error before first say → fallback (not remembered)', () async {
    var unsupported = false;
    final p = FakeClipPlayer(clipMs: 10);
    final res = await session(p, mode: 'err-before', onUnsupported: () => unsupported = true).run();
    expect(res.path, 'fallback-error');
    expect(unsupported, isFalse);
    expect(server.hits['/api/v1/ai/chat'], 1);
    expect(p.played, [0, 1]);
  });

  test('done without say → text spoken via TTS head/tail', () async {
    final p = FakeClipPlayer(clipMs: 10);
    final res = await session(p, mode: 'doneonly').run();
    expect(res.path, 'stream');
    expect(p.played, [0, 1]);
    expect(server.hits['/api/v1/ai/chat'], isNull);
  });

  test('error after first say → keep what was said, no fallback, no repeat', () async {
    for (final mode in ['err-mid', 'drop-mid']) {
      server.hits.clear();
      final p = FakeClipPlayer(clipMs: 10);
      final res = await session(p, mode: mode).run();
      expect(res.path, 'stream', reason: mode);
      expect(p.played, [0], reason: mode);
      expect(res.text, 'Auksion yerlar: jami 19 649 ta.', reason: mode);
      expect(server.hits['/api/v1/ai/chat'], isNull, reason: mode);
    }
  });

  test('stalled stream (idle timeout) before say → fallback', () async {
    final p = FakeClipPlayer(clipMs: 10);
    final res = await session(p, mode: 'stall', idle: const Duration(milliseconds: 400)).run();
    expect(res.path, 'fallback-error');
    expect(p.played, [0, 1]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.streamAborted, 1); // stalled socket was actively closed by the client
  });

  test('cancel mid-answer closes the HTTP stream and stops audio at once', () async {
    final p = FakeClipPlayer(clipMs: 5000);
    final s = session(p, mode: 'ok');
    final fut = s.run();
    // wait for sentence 0 to start
    while (p.played.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final sw = Stopwatch()..start();
    await s.cancel();
    final res = await fut.timeout(const Duration(seconds: 2));
    expect(res.cancelled, isTrue);
    expect(sw.elapsedMilliseconds, lessThan(1000));
    expect(p.played, [0]);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(p.played, [0]); // nothing stale plays later
    expect(server.streamAborted, greaterThanOrEqualTo(1));
  });

  test('stale keep-alive connection on /ai/chat-stream is retried once (no fallback)', () async {
    var failed = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.path == '/ai/chat-stream' && failed == 0) {
        failed++;
        return h.reject(DioException(
            requestOptions: o, type: DioExceptionType.unknown, error: const SocketException('Connection reset by peer')));
      }
      h.next(o);
    }));
    final p = FakeClipPlayer(clipMs: 10);
    final res = await session(p).run();
    expect(failed, 1);
    expect(res.path, 'stream');
    expect(server.hits['/api/v1/ai/chat-stream'], 1);
    expect(server.hits['/api/v1/ai/chat'], isNull);
  });

  test('withNetRetry retries only retryable, fast errors', () async {
    var n = 0;
    final ok = await withNetRetry(() async {
      if (n++ == 0) {
        throw DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError);
      }
      return 42;
    });
    expect(ok, 42);
    n = 0;
    await expectLater(
        withNetRetry(() async {
          n++;
          throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: RequestOptions(), statusCode: 400));
        }),
        throwsA(isA<DioException>()));
    expect(n, 1); // 4xx is not retried
  });

  test('fallback persona answer plays the cached lip-sync video instead of TTS', () async {
    server.mode = 'persona';
    String? videoText;
    final p = FakeClipPlayer(clipMs: 10);
    final s = AnswerSession(
      dio: dio,
      player: p,
      q: 'isming nima',
      lang: 'uz',
      useStream: false,
      fetchTts: (t) async => MockVoiceServer.fakeMp3(t),
      personaVideo: (t) async {
        videoText = t;
        return true;
      },
    );
    final res = await s.run();
    expect(res.persona, isTrue);
    expect(s.personaVideoPlayed, isTrue);
    expect(videoText, startsWith('Auksion yerlar'));
    expect(p.played, isEmpty);

    // no cached video → normal TTS
    final p2 = FakeClipPlayer(clipMs: 10);
    final s2 = AnswerSession(
      dio: dio,
      player: p2,
      q: 'isming nima',
      lang: 'uz',
      useStream: false,
      fetchTts: (t) async => MockVoiceServer.fakeMp3(t),
      personaVideo: (t) async => false,
    );
    await s2.run();
    expect(s2.personaVideoPlayed, isFalse);
    expect(p2.played, [0, 1]);
  });

  test('persona flag is reported from done', () async {
    final p = FakeClipPlayer(clipMs: 10);
    final res = await session(p, mode: 'persona').run();
    expect(res.persona, isTrue);
    expect(res.table, isNull);
    expect(p.played, [0, 1]);
  });
}
