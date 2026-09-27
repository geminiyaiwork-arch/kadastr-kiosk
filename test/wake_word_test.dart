import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/features/ai/wake_word.dart';
import 'package:kadastr_kiosk/features/ai/wav_tools.dart';

Uint8List _wav({required int ms, int rate = 16000, int headerPad = 0, double amp = 0}) {
  final n = rate * ms ~/ 1000;
  final pcm = Uint8List(n * 2);
  final bd = ByteData.sublistView(pcm);
  for (var i = 0; i < n; i++) {
    bd.setInt16(i * 2, (amp * 32767 * sin(i / 8)).round(), Endian.little);
  }
  final w = buildWav(pcm, sampleRate: rate);
  if (headerPad == 0) return w;
  // record_windows uslubi: fmt chunk 18 bayt (cbSize bilan) → sarlavha 46 bayt
  final out = BytesBuilder()
    ..add(w.sublist(0, 16))
    ..add([18, 0, 0, 0])
    ..add(w.sublist(20, 36))
    ..add([0, 0])
    ..add(w.sublist(36));
  final b = out.toBytes();
  ByteData.sublistView(b).setUint32(4, b.length - 8, Endian.little);
  return b;
}

void main() {
  group('stripWakeWord', () {
    test('wake + question', () {
      expect(stripWakeWord('Alomat, auksion yerlar nechta?'), 'auksion yerlar nechta');
      expect(stripWakeWord('Аломат, сколько аукционов?'), 'сколько аукционов');
      expect(stripWakeWord('Salom Alomat, qalaysiz'), 'qalaysiz');
    });
    test('bare wake variants', () {
      for (final s in ['Alomat', 'Alomat!', 'Alomatxon.', 'Alomat xon', 'olomat', '«Alomat»', 'Alomat-xon', 'Alomatjon', 'Alo mat']) {
        expect(stripWakeWord(s), '', reason: s);
      }
    });
    test('split / quoted / hyphenated forms keep the command', () {
      expect(stripWakeWord('"Alomat", telefonlarni och'), 'telefonlarni och');
      expect(stripWakeWord('Alo mat, auksion'), 'auksion');
      expect(stripWakeWord('Alomat-xon qalay'), 'qalay');
    });
    test('no wake: ordinary speech and the plural noun "alomatlar"', () {
      expect(stripWakeWord('Bugun havo yaxshi'), isNull);
      expect(stripWakeWord('Kasallik alomatlari haqida gapir'), isNull);
      expect(stripWakeWord('bir ikki uch alomat'), isNull); // 4-so'z — hisobga olinmaydi
      expect(stripWakeWord(''), isNull);
    });
  });

  group('wav tools', () {
    test('parses 44- and 46-byte headers', () {
      final a = parseWav(_wav(ms: 100))!;
      expect(a.dataOffset, 44);
      expect(a.sampleRate, 16000);
      final b = parseWav(_wav(ms: 100, headerPad: 2))!;
      expect(b.dataOffset, 46);
      expect(b.dataLength, 3200);
    });

    test('trimWavStart cuts leading audio and rebuilds a canonical header', () {
      final w = _wav(ms: 2000, headerPad: 2);
      final t = trimWavStart(w, 1500);
      final info = parseWav(t)!;
      expect(info.dataOffset, 44);
      expect(info.dataLength, 16000 * 2 * 500 ~/ 1000);
      // too little left → original returned
      expect(identical(trimWavStart(w, 1900), w), isTrue);
      expect(identical(trimWavStart(w, -5), w), isTrue);
    });

    test('wavLevels: silence vs tone', () {
      expect(wavLevels(_wav(ms: 200)).$1, lessThan(-100));
      final tone = wavLevels(_wav(ms: 200, amp: 0.1));
      expect(tone.$1, closeTo(-23, 1.5));
    });
  });
}
