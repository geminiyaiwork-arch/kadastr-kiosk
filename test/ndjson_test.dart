import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/features/ai/answer_session.dart';
import 'package:kadastr_kiosk/features/ai/ndjson.dart';

Stream<Uint8List> _chunks(List<int> bytes, List<int> cuts) async* {
  var prev = 0;
  for (final c in [...cuts, bytes.length]) {
    yield Uint8List.fromList(bytes.sublist(prev, c));
    prev = c;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('decodeNdjson', () {
    test('lines split across chunks + multi-byte UTF-8 split mid-character', () async {
      const a = {'t': 'say', 'i': 0, 'text': 'Qo‘rg‘ontepa — Кургантепа ✓'};
      const b = {'t': 'done', 'out': {'text': 'Ўзбекистон'}};
      final bytes = utf8.encode('${jsonEncode(a)}\n${jsonEncode(b)}\n');
      // every possible single cut + a byte-by-byte stream
      for (var cut = 1; cut < bytes.length; cut++) {
        final got = await decodeNdjson(_chunks(bytes, [cut])).toList();
        expect(got, [a, b], reason: 'cut at $cut');
      }
      final byteByByte = await decodeNdjson(_chunks(bytes, [for (var i = 1; i < bytes.length; i++) i])).toList();
      expect(byteByByte, [a, b]);
    });

    test('CRLF, blank lines, trailing line without newline', () async {
      final bytes = utf8.encode('{"t":"ping"}\r\n\r\n  \n{"t":"say","i":1,"text":"x"}');
      final got = await decodeNdjson(_chunks(bytes, [5, 17])).toList();
      expect(got, [
        {'t': 'ping'},
        {'t': 'say', 'i': 1, 'text': 'x'},
      ]);
    });

    test('malformed line is skipped and reported, stream continues', () async {
      final bad = <String>[];
      final bytes = utf8.encode('{"t":"say","i":0,"text":"a"}\n{broken\n[1,2]\n{"t":"done","out":{}}\n');
      final got = await decodeNdjson(_chunks(bytes, [3, 40]), onMalformed: (l, _) => bad.add(l)).toList();
      expect(got.map((e) => e['t']), ['say', 'done']);
      expect(bad, ['{broken', '[1,2]']);
    });
  });

  group('parseChatStreamEvent', () {
    test('say with base64 audio, null audio, broken base64', () {
      final ok = parseChatStreamEvent({'t': 'say', 'i': 2, 'text': 'Salom.', 'audio': base64Encode([1, 2, 3])});
      expect(ok, isA<SayEvent>());
      expect((ok as SayEvent).index, 2);
      expect(ok.audio, [1, 2, 3]);
      final nul = parseChatStreamEvent({'t': 'say', 'i': 0, 'text': 'a', 'audio': null}) as SayEvent;
      expect(nul.audio, isNull);
      final broken = parseChatStreamEvent({'t': 'say', 'i': 0, 'text': 'a', 'audio': '%%%'}) as SayEvent;
      expect(broken.audio, isNull);
    });

    test('done / error / ping / unknown', () {
      final d = parseChatStreamEvent({
        't': 'done',
        'out': {'text': 'x', 'persona': true}
      });
      expect(d, isA<DoneEvent>());
      expect((d as DoneEvent).out['persona'], true);
      expect(parseChatStreamEvent({'t': 'error', 'error': 'boom'}), isA<ErrorEvent>());
      expect(parseChatStreamEvent({'t': 'ping'}), isNull);
      expect(parseChatStreamEvent({'t': 'wat'}), isNull);
      expect(parseChatStreamEvent({'t': 'say', 'text': 'no index'}), isNull);
    });
  });
}
