import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'speech_queue.dart';

/// IKKI `AudioPlayer` navbatma-navbat: biri jumlani o'ynayotganda ikkinchisi keyingi
/// jumlani oldindan ochib (setSource → dekoder tayyor) turadi → jumlalar orasida
/// eshitiladigan pauza yo'q (faqat `resume` ~10 ms).
///
/// Tezlik tafsilotlari:
/// - `positionUpdater = null`: audioplayers standart FramePositionUpdater o'ynash
///   davomida HAR KADRda yangi kadr so'raydi + platforma-kanal chaqiradi (bizga
///   pozitsiya kerak emas) — UI keraksiz 60 fps'da ishlab turardi.
/// - Vaqtinchalik fayl `flush` siz yoziladi (fsync shart emas — o'sha mashina o'qiydi).
/// - ReleaseMode.release (standart): tugagач manba bo'shaydi → fayl darhol o'chadi.
class AudioClipPlayer implements ClipPlayer {
  AudioClipPlayer({this.onTrace}) {
    for (final p in _players) {
      p.positionUpdater = null;
    }
  }

  /// Diagnostika: 'prepared' / 'resumed' / 'ended' / 'stopped' hodisalari (latency o'lchovi).
  final void Function(SpeechClip clip, String event)? onTrace;

  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  final List<SpeechClip?> _slotClip = [null, null];
  final List<Future<bool>?> _slotReady = [null, null];
  final List<String?> _slotFile = [null, null];
  final Set<String> _trash = {};
  int _playingSlot = -1;
  int _gen = 0;
  int _seq = 0;
  Completer<void>? _stopSig;
  bool _disposed = false;

  static String get _tmp => Directory.systemTemp.path;
  static String get _sep => Platform.pathSeparator;

  int _slotOf(SpeechClip c) {
    for (var i = 0; i < 2; i++) {
      if (identical(_slotClip[i], c)) return i;
    }
    return -1;
  }

  int _otherSlot() {
    if (_playingSlot == 0) return 1;
    if (_playingSlot == 1) return 0;
    return _slotClip[0] == null ? 0 : (_slotClip[1] == null ? 1 : 0);
  }

  void _dropSlot(int s) {
    final f = _slotFile[s];
    _slotClip[s] = null;
    _slotReady[s] = null;
    _slotFile[s] = null;
    if (f != null) _trash.add(f);
  }

  /// O'ynab bo'lingan fayllarni o'chiradi (hali ochiq bo'lsa keyingi safar urinadi).
  void _sweepTrash() {
    if (_trash.isEmpty) return;
    for (final f in _trash.toList()) {
      if (_slotFile.contains(f)) continue;
      try {
        final file = File(f);
        if (file.existsSync()) file.deleteSync();
        _trash.remove(f);
      } catch (_) {
        // Windows: fayl hali ochiq — keyingi yuklashda qayta urinamiz
      }
    }
  }

  Future<bool> _load(int s, SpeechClip c) {
    final prevFile = _slotFile[s];
    _slotClip[s] = c;
    _slotFile[s] = null;
    if (prevFile != null) _trash.add(prevFile);
    final gen = _gen;
    final job = () async {
      final bytes = c.bytes;
      if (bytes == null || bytes.isEmpty) return false;
      final path = '$_tmp${_sep}kadastr_clip_${pid}_${++_seq}.mp3';
      await File(path).writeAsBytes(bytes);
      if (gen != _gen || !identical(_slotClip[s], c)) {
        _trash.add(path);
        return false;
      }
      _slotFile[s] = path;
      await _players[s].setSource(DeviceFileSource(path)).timeout(const Duration(seconds: 6));
      _sweepTrash(); // oldingi manba almashdi → eski fayl endi yopiq
      onTrace?.call(c, 'prepared');
      return gen == _gen && identical(_slotClip[s], c);
    }();
    final safe = job.catchError((Object _) => false);
    _slotReady[s] = safe;
    return safe;
  }

  /// Birinchi haqiqiy javobdan OLDIN Media Foundation MP3 dekoderini "isitadi"
  /// (ilova ochilgач birinchi setSource sezilarli sekinroq). Ovoz chiqmaydi.
  Future<void> warmUp(Uint8List bytes) async {
    if (_disposed || _playingSlot >= 0 || _slotClip[1] != null) return;
    final c = SpeechClip(-2, '')
      ..bytes = bytes
      ..resolved = true;
    final ok = await _load(1, c);
    if (identical(_slotClip[1], c)) {
      try {
        if (ok) await _players[1].stop(); // release → fayl yopiladi
      } catch (_) {}
      if (identical(_slotClip[1], c)) _dropSlot(1);
      _sweepTrash();
    }
  }

  @override
  Future<void> preload(SpeechClip c) async {
    if (_disposed || c.bytes == null || _slotOf(c) >= 0) return;
    final s = _otherSlot();
    if (s == _playingSlot) return;
    await _load(s, c);
  }

  @override
  Future<void> play(SpeechClip c) async {
    if (_disposed) return;
    final gen = _gen;
    var s = _slotOf(c);
    if (s < 0) {
      s = _otherSlot();
      unawaited(_load(s, c));
    }
    _playingSlot = s; // SINXRON band qilamiz — keyingi preload boshqa slotga tushadi
    final stopSig = _stopSig ??= Completer<void>();
    var natural = false;
    try {
      final ok = await (_slotReady[s] ?? Future.value(false));
      if (gen != _gen) return;
      if (!ok) throw StateError('clip ${c.id}: prepare failed');
      final p = _players[s];
      final done = p.onPlayerComplete.first.then((_) => natural = true);
      await p.resume();
      onTrace?.call(c, 'resumed');
      Duration? dur;
      try {
        dur = await p.getDuration();
      } catch (_) {}
      final cap = (dur != null && dur > Duration.zero)
          ? dur + const Duration(milliseconds: 1500)
          : Duration(seconds: 15 + c.text.length ~/ 10);
      await Future.any<void>([done, stopSig.future, Future<void>.delayed(cap)]);
      onTrace?.call(c, natural ? 'ended' : 'stopped');
      if (!natural && gen == _gen) {
        try {
          await p.stop(); // cap tugadi — o'z ovozi ustma-ust tushmasin
        } catch (_) {}
      }
    } finally {
      if (gen == _gen) {
        if (_playingSlot == s) _playingSlot = -1;
        if (identical(_slotClip[s], c)) _dropSlot(s);
        _sweepTrash();
      }
    }
  }

  @override
  Future<void> stop() async {
    _gen++;
    final sig = _stopSig;
    _stopSig = null;
    if (sig != null && !sig.isCompleted) sig.complete();
    _playingSlot = -1;
    _dropSlot(0);
    _dropSlot(1);
    await Future.wait(_players.map((p) => p.stop().catchError((Object _) {})));
    _sweepTrash();
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    for (final p in _players) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _sweepTrash();
  }

  /// Oldingi ishga tushirishlardan qolgan vaqtinchalik mp3'larni tozalaydi (disk to'lmasin).
  static Future<void> sweepStaleTempFiles() async {
    try {
      final now = DateTime.now();
      await for (final e in Directory(_tmp).list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        final ours = (name.startsWith('kadastr_clip_') || name.startsWith('kadastr_tts_')) && name.endsWith('.mp3');
        if (!ours) continue;
        try {
          if (now.difference(e.statSync().modified).inMinutes >= 2) await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
