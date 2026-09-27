// Linux/Windows desktop'da HAQIQIY audioplayers plagini bilan navbatni tekshiradi
// (mock serverga qarshi): tartib, jumlalar orasidagi bo'shliq, filler, 404-fallback, bekor.
//   dart run tool/mock_voice_server.dart --port 8787 &
//   flutter run -d linux -t tool/audio_probe_main.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kadastr_kiosk/features/ai/answer_session.dart';
import 'package:kadastr_kiosk/features/ai/audio_clip_player.dart';

const _origin = String.fromEnvironment('KIOSK_API_ORIGIN', defaultValue: 'http://127.0.0.1:8787');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('audio probe')))));
  final sw = Stopwatch()..start();
  final trace = <String>[];
  final ends = <int, int>{};
  final gaps = <int>[];
  var lastEnd = -1;
  final player = AudioClipPlayer(onTrace: (c, ev) {
    final t = sw.elapsedMilliseconds;
    trace.add('${c.id}:$ev@$t');
    if (ev == 'ended') {
      ends[c.id] = t;
      lastEnd = t;
    }
    if (ev == 'resumed' && lastEnd >= 0 && t - lastEnd < 3000) gaps.add(t - lastEnd);
  });
  final dio = Dio(BaseOptions(baseUrl: '$_origin/api/v1'));
  Future<Uint8List?> tts(String text) async {
    final r = await dio.get<List<int>>('/tts/synthesize',
        queryParameters: {'text': text, 'voice': 'madina', 'lang': 'uz'},
        options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(r.data!);
  }

  final filler = await tts('Bir soniya.');
  var ok = true;
  for (final mode in ['ok', 'slow', '404', 'noaudio', 'cancel']) {
    trace.clear();
    gaps.clear();
    lastEnd = -1;
    dio.options.headers['X-Mock-Mode'] = mode == 'cancel' ? 'ok' : mode;
    final t0 = sw.elapsedMilliseconds;
    var firstAudio = -1;
    final s = AnswerSession(
      dio: dio,
      player: player,
      q: 'auksion yerlar nechta',
      lang: 'uz',
      voice: 'madina',
      fetchTts: tts,
      pickFiller: () => ('Bir soniya.', filler!),
      fillerAfter: const Duration(milliseconds: 1100),
      onClipStart: (c) {
        if (firstAudio < 0) firstAudio = sw.elapsedMilliseconds - t0;
      },
    );
    if (mode == 'cancel') {
      Future.delayed(const Duration(milliseconds: 900), s.cancel);
    }
    final res = await s.run();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final played = s.queue.playedIds;
    stdout.writeln('[probe] mode=$mode path=${res.path} cancelled=${res.cancelled} played=$played '
        'first_audio_ms=$firstAudio gaps_ms=$gaps');
    stdout.writeln('[probe]   trace=${trace.join(' ')}');
    final expectPlayed = {
      'ok': [0, 1, 2],
      'slow': [-1, 0, 1, 2],
      '404': [0, 1],
      'noaudio': [0, 1, 2],
      'cancel': <int>[],
    }[mode]!;
    if (mode != 'cancel' && played.join(',') != expectPlayed.join(',')) ok = false;
    if (mode == 'cancel' && (!res.cancelled || trace.any((e) => e.contains(':resumed@') && !e.startsWith('0:')))) ok = false;
  }
  stdout.writeln('[probe] RESULT ${ok ? 'PASS' : 'FAIL'}');
  await player.dispose();
  exit(ok ? 0 : 1);
}
