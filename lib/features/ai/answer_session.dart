import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'ndjson.dart';
import 'speech_queue.dart';

// ============================================================================
//  /ai/chat-stream (NDJSON) hodisalari — CONTRACT.md §1
// ============================================================================

sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// `{"t":"say","i":0,"text":"...","audio":"<base64 mp3>|null"}`
class SayEvent extends ChatStreamEvent {
  const SayEvent(this.index, this.text, this.audio);
  final int index;
  final String text;
  final Uint8List? audio; // null → klient /tts/synthesize dan o'zi oladi
}

/// `{"t":"done","out":{...}}` — `out` = /ai/chat javobi bilan AYNAN bir xil shakl.
class DoneEvent extends ChatStreamEvent {
  const DoneEvent(this.out);
  final Map<String, dynamic> out;
}

/// `{"t":"error","error":"..."}`
class ErrorEvent extends ChatStreamEvent {
  const ErrorEvent(this.message);
  final String message;
}

/// NDJSON obyektini hodisaga aylantiradi. `ping`/noma'lum → null (e'tiborsiz).
ChatStreamEvent? parseChatStreamEvent(Map<String, dynamic> m) {
  switch (m['t']) {
    case 'say':
      final i = m['i'];
      if (i is! num) return null;
      final text = (m['text'] ?? '').toString();
      Uint8List? audio;
      final a = m['audio'];
      if (a is String && a.isNotEmpty) {
        try {
          audio = base64Decode(a);
        } catch (_) {
          audio = null; // buzuq base64 → klient TTS'ni o'zi oladi
        }
      }
      return SayEvent(i.toInt(), text, audio);
    case 'done':
      final out = m['out'];
      return DoneEvent(out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{});
    case 'error':
      return ErrorEvent((m['error'] ?? 'error').toString());
    default:
      return null;
  }
}

/// Server bu endpointni bilmaydi (eski server: 404/405/501) — sessiya davomida eslab qolinadi.
class ChatStreamUnsupported implements Exception {
  const ChatStreamUnsupported(this.status);
  final int status;
  @override
  String toString() => 'ChatStreamUnsupported($status)';
}

/// Vaqtinchalik xato (5xx, tarmoq, timeout) — shu savol uchun eski yo'lga tushiladi.
class ChatStreamFailed implements Exception {
  const ChatStreamFailed(this.reason);
  final String reason;
  @override
  String toString() => 'ChatStreamFailed($reason)';
}

/// `POST /ai/chat-stream` ni ochadi va hodisalar oqimini qaytaradi.
/// [idleTimeout] — ikki bo'lak orasidagi eng uzun jimlik (server `ping` yuboradi).
Future<Stream<ChatStreamEvent>> openChatStream(
  Dio dio, {
  required String q,
  required String lang,
  String? voice,
  CancelToken? cancelToken,
  Duration headersTimeout = const Duration(seconds: 15),
  Duration idleTimeout = const Duration(seconds: 12),
}) async {
  final Response<ResponseBody> r;
  try {
    r = await dio.post<ResponseBody>(
      '/ai/chat-stream',
      data: {'q': q, 'lang': lang, if (voice != null && voice.isNotEmpty) 'voice': voice},
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        receiveTimeout: headersTimeout, // javob SARLAVHASI kelguncha (tana oqimi alohida)
        headers: {'Accept': 'application/x-ndjson'},
      ),
    );
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) rethrow;
    throw ChatStreamFailed('${e.type.name}: ${e.message ?? e.error}');
  }
  final code = r.statusCode ?? 0;
  final body = r.data;
  if (code != 200 || body == null) {
    // tanani tashlab, ulanishni yopamiz
    try {
      await body?.stream.listen(null).cancel();
    } catch (_) {}
    if (code == 404 || code == 405 || code == 501) throw ChatStreamUnsupported(code);
    throw ChatStreamFailed('http $code');
  }
  final ctype = (body.headers['content-type'] ?? const <String>[]).join(',').toLowerCase();
  if (ctype.contains('text/html')) {
    // proksi xato sahifasi (200 bo'lsa ham) — NDJSON emas
    try {
      await body.stream.listen(null).cancel();
    } catch (_) {}
    throw const ChatStreamFailed('not ndjson');
  }
  final timed = body.stream.timeout(idleTimeout, onTimeout: (sink) {
    sink.addError(ChatStreamFailed('idle ${idleTimeout.inMilliseconds}ms'));
    sink.close();
  });
  return decodeNdjson(timed).map(parseChatStreamEvent).where((e) => e != null).cast<ChatStreamEvent>();
}

// ============================================================================
//  AnswerSession — bitta savolga javob: stream (yoki eski yo'l) + navbat + filler
// ============================================================================

class AnswerResult {
  AnswerResult({
    required this.text,
    required this.table,
    required this.persona,
    required this.out,
    required this.path,
    required this.cancelled,
  });

  /// To'liq javob matni (done.out.text yoki aytilgan jumlalar yig'indisi).
  final String text;
  final List<List<dynamic>>? table;
  final bool persona;
  final Map<String, dynamic> out;

  /// 'stream' | 'fallback' | 'fallback-unsupported' | 'fallback-error'
  final String path;
  final bool cancelled;
}

/// Filler (qisqa "Bir soniya.") manbai: (matn, audio) yoki null (tayyor emas).
typedef FillerPicker = (String, Uint8List)? Function();

/// Bitta savol-javob sessiyasi. Plaginlarga bog'liq emas (ClipPlayer inject qilinadi)
/// → test qilinadi.
///
/// Oqim:
/// 1. `/ai/chat-stream` (agar sessiyada 404 bo'lmagan bo'lsa): har `say` kelishi bilan
///    matn ko'rsatiladi va audio navbatga qo'yiladi (0-jumla DARHOL o'ynaydi);
///    `done` → jadval/persona. Birinchi `say`dan OLDIN xato/404 → eski yo'l.
/// 2. Eski yo'l: `/ai/chat` → bosh-jumla + davomi TTS (parallel) → navbat.
/// 3. [fillerAfter] ichida hech qanday audio kelmasa — bitta filler.
class AnswerSession {
  AnswerSession({
    required this.dio,
    required this.player,
    required this.q,
    required this.lang,
    required this.fetchTts,
    this.voice,
    this.useStream = true,
    this.onStreamUnsupported,
    this.pickFiller,
    this.fillerAfter,
    this.onText,
    this.onClipStart,
    this.onFirstEvent,
    this.log,
    this.chatTimeout = const Duration(seconds: 20),
    this.streamIdleTimeout = const Duration(seconds: 12),
  });

  final Dio dio;
  final ClipPlayer player;
  final String q;
  final String lang;
  final String? voice;
  final bool useStream;
  final void Function()? onStreamUnsupported;
  final Future<Uint8List?> Function(String text) fetchTts;
  final FillerPicker? pickFiller;
  final Duration? fillerAfter;

  /// Progressiv matn: hozirgacha kelgan jumlalar (to'liq bo'lsa [complete]=true).
  final void Function(String textSoFar, {required bool complete, List<List<dynamic>>? table, bool persona})? onText;
  final void Function(SpeechClip clip)? onClipStart;
  final void Function(String kind)? onFirstEvent;
  final void Function(String msg)? log;
  final Duration chatTimeout;

  /// Oqimda ikki hodisa orasidagi eng uzun jimlik (server har ~5s `ping` yuboradi).
  final Duration streamIdleTimeout;

  final CancelToken _cancel = CancelToken();
  // Oqim uchun ALOHIDA token: xato/timeout bo'lsa soket darhol yopiladi (obunani bekor
  // qilishning o'zi Dart HttpClient'da ulanishni yopmaydi — o'lchab tekshirildi), lekin
  // eski yo'l (/ai/chat) so'rovi bekor bo'lmaydi.
  final CancelToken _streamCancel = CancelToken();
  late final SpeechQueue queue = SpeechQueue(player, onClipStart: _clipStarted, log: log);
  Timer? _fillerTimer;
  bool _cancelled = false;
  final _spoken = StringBuffer();
  final _texts = <int, String>{};

  /// Filler + hamma jumlalar (aks-sado filtri uchun) — aytilgan TO'LIQ matn.
  String get spokenText => _spoken.toString().trim();
  bool get isCancelled => _cancelled;

  void _addSpoken(String t) {
    final s = t.trim();
    if (s.isEmpty) return;
    if (_spoken.isNotEmpty) _spoken.write(' ');
    _spoken.write(s);
  }

  void _clipStarted(SpeechClip c) {
    _fillerTimer?.cancel();
    onClipStart?.call(c);
  }

  /// Hammasini to'xtatadi: HTTP oqimi yopiladi, navbat va audio to'xtaydi.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _fillerTimer?.cancel();
    if (!_cancel.isCancelled) _cancel.cancel('cancelled');
    if (!_streamCancel.isCancelled) _streamCancel.cancel('cancelled');
    await queue.cancel();
  }

  void _armFiller() {
    final after = fillerAfter;
    final pick = pickFiller;
    if (after == null || pick == null) return;
    _fillerTimer = Timer(after, () {
      if (_cancelled || queue.realAudioReady || queue.isPlaying) return;
      final f = pick();
      if (f == null) return;
      if (queue.offerFiller(f.$1, f.$2)) {
        _addSpoken(f.$1);
        log?.call('filler "${f.$1}"');
      }
    });
  }

  String _joined() {
    final keys = _texts.keys.toList()..sort();
    return keys.map((k) => _texts[k]!.trim()).where((s) => s.isNotEmpty).join(' ');
  }

  static List<List<dynamic>>? _table(Map<String, dynamic> m) {
    final t = m['table'];
    if (t is List && t.isNotEmpty) {
      return t.whereType<List>().map((e) => e.cast<dynamic>()).toList();
    }
    return null;
  }

  /// Savolni yuboradi, javobni gapiradi, hammasi tugaganda (yoki bekor) qaytadi.
  Future<AnswerResult> run() async {
    _armFiller();
    String path = 'stream';
    Map<String, dynamic>? out;
    var sawSay = false;
    if (useStream) {
      try {
        final events = await openChatStream(dio,
            q: q, lang: lang, voice: voice, cancelToken: _streamCancel, idleTimeout: streamIdleTimeout);
        var first = true;
        await for (final ev in events) {
          if (_cancelled) break;
          if (first) {
            first = false;
            onFirstEvent?.call(ev is SayEvent ? 'say' : ev is DoneEvent ? 'done' : 'error');
          }
          switch (ev) {
            case SayEvent(:final index, :final text, :final audio):
              sawSay = true;
              _texts[index] = text;
              _addSpoken(text);
              onText?.call(_joined(), complete: false);
              final a = (audio != null && audio.length >= 200) ? audio : null;
              queue.add(index, text, a ?? (text.trim().isEmpty ? null : fetchTts(text)));
            case DoneEvent(out: final o):
              out = o;
            case ErrorEvent(:final message):
              if (!sawSay) throw ChatStreamFailed('server: $message');
              log?.call('stream error after say: $message');
          }
          if (out != null) break;
        }
        if (!_cancelled && !sawSay && out == null) throw const ChatStreamFailed('empty stream');
      } on ChatStreamUnsupported catch (e) {
        log?.call('chat-stream unsupported (${e.status}) → /ai/chat');
        onStreamUnsupported?.call();
        path = 'fallback-unsupported';
      } catch (e) {
        if (_cancelled) return _result('', null, false, const {}, path, true);
        // uzilgan/osilib qolgan oqim soketini yopamiz
        if (!_streamCancel.isCancelled) _streamCancel.cancel('stream error');
        if (sawSay) {
          // Gapirish boshlangan — takrorlamaymiz; aytilganini tugatamiz.
          log?.call('stream broke after say: $e');
        } else {
          log?.call('chat-stream failed before say: $e → /ai/chat');
          path = 'fallback-error';
        }
      }
    } else {
      path = 'fallback';
    }

    if (_cancelled) return _result('', null, false, const {}, path, true);

    if (path != 'stream') {
      out = await _fallbackChat();
      if (_cancelled) return _result('', null, false, const {}, path, true);
    }

    final o = out ?? const <String, dynamic>{};
    final persona = o['persona'] == true;
    final table = _table(o);
    var full = (o['text'] ?? '').toString().trim();
    if (full.isEmpty) full = _joined();
    onText?.call(full, complete: true, table: table, persona: persona);
    if (!sawSay && full.isNotEmpty) {
      // Eski yo'l (yoki `say`siz `done`): matn birdaniga, audio bosh-jumla + davomi
      // parallel yuklanadi (server prewarm bilan bir xil bo'linish → kesh mos).
      final clean = full.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final sp = clean.length > 800 ? clean.substring(0, 800) : clean;
      final (head, tail) = splitHeadTail(sp);
      _addSpoken(sp);
      queue.add(0, head, fetchTts(head));
      if (tail != null) queue.add(1, tail, fetchTts(tail));
    }
    queue.close();
    await queue.done;
    _fillerTimer?.cancel();
    return _result(full, table, persona, o, path, _cancelled);
  }

  Future<Map<String, dynamic>?> _fallbackChat() async {
    try {
      final r = await dio.post(
        '/ai/chat',
        data: {'q': q, 'lang': lang},
        cancelToken: _cancel,
        options: Options(receiveTimeout: chatTimeout),
      );
      final d = r.data;
      if (d is Map) return Map<String, dynamic>.from(d);
      if (d is String && d.isNotEmpty) {
        final j = jsonDecode(d);
        if (j is Map) return Map<String, dynamic>.from(j);
      }
    } catch (e) {
      log?.call('/ai/chat failed: $e');
    }
    return null;
  }

  AnswerResult _result(String text, List<List<dynamic>>? table, bool persona, Map<String, dynamic> out, String path,
          bool cancelled) =>
      AnswerResult(text: text, table: table, persona: persona, out: out, path: path, cancelled: cancelled);
}
