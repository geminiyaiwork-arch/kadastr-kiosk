import 'dart:async';
import 'dart:typed_data';

/// Bitta gapiriladigan bo'lak (jumla). [id] — tartib raqami (0,1,2…); filler = -1.
class SpeechClip {
  SpeechClip(this.id, this.text, {this.isFiller = false});
  final int id;
  final String text;
  final bool isFiller;

  /// Audio (mp3). `resolved == true` bo'lgach o'rnatiladi; null = audio yo'q (o'tkaziladi).
  Uint8List? bytes;
  bool resolved = false;

  /// O'ynatuvchi (ClipPlayer) uchun ixtiyoriy joy (masalan vaqtinchalik fayl yo'li).
  Object? playerData;

  @override
  String toString() => 'SpeechClip($id${isFiller ? ',filler' : ''})';
}

/// Audio o'ynatuvchi abstraksiyasi — navbat mantig'ini plaginsiz test qilish uchun.
abstract class ClipPlayer {
  /// Keyingi bo'lakni oldindan tayyorlaydi (dekoder ochiladi) — `play` darhol boshlansin.
  Future<void> preload(SpeechClip clip);

  /// Bo'lakni o'ynatadi; tugaganda YOKI [stop] chaqirilganda tugaydi. Xato → throw.
  Future<void> play(SpeechClip clip);

  /// Hamma narsani darhol to'xtatadi (o'ynayotgan `play` ham tugaydi).
  Future<void> stop();
}

/// JAVOB NAVBATI — jumlalar KELISH tartibidan qat'i nazar `id` bo'yicha ketma-ket,
/// oraliqsiz o'ynaydi:
/// - bo'lak audiosi kelishi bilan (yoki oldingisi tugashi bilan) darhol boshlanadi;
/// - joriy bo'lak o'ynayotganda keyingisi oldindan tayyorlanadi (preload);
/// - hali hech narsa boshlanmagan bo'lsa FILLER ("Bir soniya.") birinchi o'ynaydi;
///   haqiqiy audio filler paytida kelsa — filler tugashi bilan boshlanadi;
/// - [close] dan keyin yetishmayotgan raqamlar (bo'shliq) o'tkazib yuboriladi;
/// - [cancel] hammasini darhol to'xtatadi.
class SpeechQueue {
  SpeechQueue(this._player, {this.onClipStart, this.log});

  final ClipPlayer _player;
  final void Function(SpeechClip clip)? onClipStart;
  final void Function(String msg)? log;

  final Map<int, SpeechClip> _clips = {};
  int _next = 0;
  bool _closed = false;
  bool _cancelled = false;
  bool _startedReal = false;
  bool _fillerUsed = false;
  SpeechClip? _filler;
  SpeechClip? _playing;
  bool _running = false;
  Completer<void>? _signal;
  final Completer<void> _done = Completer<void>();
  final List<int> playedIds = [];

  /// Navbat tugadi (hammasi o'ynaldi) yoki bekor qilindi.
  Future<void> get done => _done.future;
  bool get startedReal => _startedReal;
  bool get fillerUsed => _fillerUsed;
  bool get cancelled => _cancelled;
  bool get closed => _closed;
  bool get isPlaying => _playing != null;

  /// Birinchi haqiqiy bo'lak audiosi tayyor (yoki allaqachon boshlangan)mi?
  bool get realAudioReady {
    if (_startedReal) return true;
    final head = _clips[_next];
    return head != null && head.resolved && head.bytes != null;
  }

  /// [id]-bo'lakni qo'shadi; audio [bytes] (tayyor yoki kelajakda). Takror/eskirgan id e'tiborsiz.
  void add(int id, String text, FutureOr<Uint8List?> bytes) {
    if (_cancelled || _closed || id < _next || _clips.containsKey(id)) return;
    final c = SpeechClip(id, text);
    _clips[id] = c;
    if (bytes is Future<Uint8List?>) {
      bytes.then((b) => _resolve(c, b), onError: (Object e) {
        log?.call('clip $id audio error: $e');
        _resolve(c, null);
      });
    } else {
      _resolve(c, bytes);
    }
    _ensureRunning();
  }

  void _resolve(SpeechClip c, Uint8List? b) {
    if (c.resolved) return;
    c.bytes = (b != null && b.isNotEmpty) ? b : null;
    c.resolved = true;
    if (_cancelled) return;
    // Oraliqsiz: joriy bo'lakdan keyingisi o'ynayotgan payt kelsa — darhol tayyorlaymiz.
    if (_playing != null && c.bytes != null && c.id == _next) {
      unawaited(_safePreload(c));
    }
    _kick();
  }

  /// Hali haqiqiy audio boshlanmagan va tayyor ham bo'lmasa — filler qo'yiladi.
  /// true = qabul qilindi (o'ynaydi).
  bool offerFiller(String text, Uint8List bytes) {
    if (_cancelled || _startedReal || _fillerUsed || bytes.isEmpty) return false;
    if (realAudioReady) return false;
    if (_closed && _clips.isEmpty) return false; // javob bo'sh tugadi
    _fillerUsed = true;
    _filler = SpeechClip(-1, text, isFiller: true)
      ..bytes = bytes
      ..resolved = true;
    _ensureRunning();
    _kick();
    return true;
  }

  /// Boshqa bo'lak kelmaydi (done). Navbat qolganini o'ynab tugaydi.
  void close() {
    if (_closed) return;
    _closed = true;
    _ensureRunning();
    _kick();
  }

  /// Darhol to'xtatish (yangi savol / sahifa almashishi / uyg'otish).
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _filler = null;
    _kick();
    try {
      await _player.stop();
    } catch (_) {}
    _finish();
  }

  void _ensureRunning() {
    if (_running || _cancelled || _done.isCompleted) return;
    _running = true;
    unawaited(_pump());
  }

  void _kick() {
    final s = _signal;
    _signal = null;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<void> _wait() => (_signal ??= Completer<void>()).future;

  Future<void> _pump() async {
    try {
      while (!_cancelled) {
        final f = _filler;
        if (f != null) {
          _filler = null;
          if (!_startedReal) await _playClip(f);
          continue;
        }
        final c = _clips[_next];
        if (c == null) {
          if (_closed) {
            final later = _clips.keys.where((k) => k > _next).toList();
            if (later.isEmpty) break;
            later.sort();
            log?.call('gap: skip $_next..${later.first - 1}');
            _next = later.first;
            continue;
          }
          await _wait();
          continue;
        }
        if (!c.resolved) {
          await _wait();
          continue;
        }
        _clips.remove(_next);
        _next++;
        if (c.bytes == null) {
          log?.call('clip ${c.id}: no audio, skipped');
          continue;
        }
        _startedReal = true;
        await _playClip(c);
      }
    } catch (e) {
      log?.call('queue pump error: $e');
    } finally {
      _running = false;
      _finish();
    }
  }

  Future<void> _playClip(SpeechClip c) async {
    if (_cancelled) return;
    _playing = c;
    try {
      onClipStart?.call(c);
    } catch (_) {}
    try {
      // play() o'z slotini SINXRON band qiladi → keyingi bo'lak boshqa slotga tayyorlanadi.
      final playing = _player.play(c);
      final nx = _clips[_next];
      if (nx != null && nx.resolved && nx.bytes != null) unawaited(_safePreload(nx));
      await playing;
      if (!_cancelled) playedIds.add(c.id);
    } catch (e) {
      log?.call('clip ${c.id} play error: $e');
    } finally {
      _playing = null;
    }
  }

  Future<void> _safePreload(SpeechClip c) async {
    try {
      await _player.preload(c);
    } catch (e) {
      log?.call('clip ${c.id} preload error: $e');
    }
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// Server prewarm (server.js) bilan AYNAN bir xil bo'linish: 25-belgidan keyingi
/// birinchi `[.!?]` + bo'shliqda kesiladi, davomi ≥20 belgi bo'lsa. Kesh mos tushsin.
(String, String?) splitHeadTail(String sp) {
  if (sp.length > 45) {
    final mm = RegExp(r'''[.!?]["')\]]?\s''').firstMatch(sp.substring(25));
    if (mm != null) {
      final cut = 25 + mm.start + mm.group(0)!.length - 1;
      final h = sp.substring(0, cut).trim(), t = sp.substring(cut).trim();
      if (h.isNotEmpty && t.length >= 20) return (h, t);
    }
  }
  return (sp, null);
}
