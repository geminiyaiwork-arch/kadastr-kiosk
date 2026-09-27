import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/features/ai/speech_queue.dart';

/// Plaginsiz o'ynatuvchi: har bo'lak [clipMs] "o'ynaydi"; stop() darhol tugatadi.
class FakeClipPlayer implements ClipPlayer {
  FakeClipPlayer({this.clipMs = 40});
  final int clipMs;
  final played = <int>[];
  final preloaded = <int>[];
  final events = <String>[];
  int stops = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  Completer<void>? _stop;

  @override
  Future<void> preload(SpeechClip clip) async {
    preloaded.add(clip.id);
    events.add('preload ${clip.id}');
  }

  @override
  Future<void> play(SpeechClip clip) async {
    final stop = _stop ??= Completer<void>();
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    played.add(clip.id);
    events.add('play ${clip.id}');
    await Future.any([Future<void>.delayed(Duration(milliseconds: clipMs)), stop.future]);
    concurrent--;
    events.add('end ${clip.id}');
  }

  @override
  Future<void> stop() async {
    stops++;
    final s = _stop;
    _stop = null;
    if (s != null && !s.isCompleted) s.complete();
  }
}

Uint8List _b(int n) => Uint8List.fromList(List.filled(300, n));

Future<Uint8List?> _later(int ms, Uint8List? v) => Future.delayed(Duration(milliseconds: ms), () => v);

void main() {
  test('plays in index order even when audio arrives out of order; never overlaps', () async {
    final p = FakeClipPlayer();
    final started = <int>[];
    final q = SpeechQueue(p, onClipStart: (c) => started.add(c.id));
    q.add(2, 'c', _later(10, _b(2)));
    q.add(1, 'b', _later(30, _b(1)));
    q.add(0, 'a', _later(60, _b(0)));
    q.close();
    await q.done;
    expect(p.played, [0, 1, 2]);
    expect(started, [0, 1, 2]);
    expect(p.maxConcurrent, 1);
  });

  test('next clip is preloaded while the current one plays (gapless)', () async {
    final p = FakeClipPlayer(clipMs: 60);
    final q = SpeechQueue(p);
    q.add(0, 'a', _b(0));
    q.add(1, 'b', _later(20, _b(1))); // arrives while 0 is playing
    q.add(2, 'c', _b(2));
    q.close();
    await q.done;
    expect(p.played, [0, 1, 2]);
    expect(p.preloaded, containsAll([1, 2]));
    // clip 1 was prepared before clip 0 finished
    expect(p.events.indexOf('preload 1'), lessThan(p.events.indexOf('end 0')));
  });

  test('first clip starts as soon as its audio arrives (does not wait for close)', () async {
    final p = FakeClipPlayer();
    final q = SpeechQueue(p);
    q.add(0, 'a', _b(0));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(p.played, [0]);
    q.close();
    await q.done;
  });

  test('missing audio (null) is skipped; gaps skipped after close', () async {
    final p = FakeClipPlayer();
    final q = SpeechQueue(p);
    q.add(0, 'a', _b(0));
    q.add(1, 'b', _later(5, null));
    q.add(3, 'd', _b(3)); // index 2 never arrives
    q.close();
    await q.done;
    expect(p.played, [0, 3]);
  });

  test('filler plays first when nothing is ready; real audio follows right after', () async {
    final p = FakeClipPlayer(clipMs: 50);
    final q = SpeechQueue(p);
    q.add(0, 'a', _later(20, _b(0))); // arrives WHILE the filler plays
    expect(q.offerFiller('Bir soniya.', _b(9)), isTrue);
    q.add(1, 'b', _b(1));
    q.close();
    await q.done;
    expect(p.played, [-1, 0, 1]);
    expect(q.fillerUsed, isTrue);
  });

  test('filler refused once real audio is ready or started, and only once', () async {
    final p = FakeClipPlayer();
    final q = SpeechQueue(p);
    q.add(0, 'a', _b(0));
    expect(q.offerFiller('x', _b(9)), isFalse); // audio already ready
    q.close();
    await q.done;
    expect(p.played, [0]);

    final q2 = SpeechQueue(FakeClipPlayer());
    expect(q2.offerFiller('x', _b(9)), isTrue);
    expect(q2.offerFiller('y', _b(8)), isFalse); // one filler per answer
    q2.close();
    await q2.done;
  });

  test('cancel stops playback immediately and completes done; later adds ignored', () async {
    final p = FakeClipPlayer(clipMs: 5000);
    final q = SpeechQueue(p);
    q.add(0, 'a', _b(0));
    q.add(1, 'b', _b(1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final sw = Stopwatch()..start();
    await q.cancel();
    await q.done;
    expect(sw.elapsedMilliseconds, lessThan(500));
    expect(p.played, [0]);
    expect(p.stops, greaterThanOrEqualTo(1));
    q.add(2, 'c', _b(2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.played, [0]);
  });

  test('empty closed queue finishes', () async {
    final q = SpeechQueue(FakeClipPlayer());
    q.close();
    await q.done.timeout(const Duration(seconds: 1));
  });

  test('splitHeadTail matches the server prewarm rule', () {
    final (h, t) = splitHeadTail('Auksion yerlar: jami 19649 ta. Eng ko‘pi — Qo‘rg‘ontepa tumani, 1812 ta.');
    expect(h, 'Auksion yerlar: jami 19649 ta.');
    expect(t, 'Eng ko‘pi — Qo‘rg‘ontepa tumani, 1812 ta.');
    expect(splitHeadTail('Qisqa javob.'), ('Qisqa javob.', null));
  });
}
