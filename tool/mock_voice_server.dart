// Lokal MOCK ovoz-server — /api/v1/ai/chat-stream (NDJSON, CONTRACT.md §1) va eski
// /ai/chat, /tts/synthesize, /stt, /health yo'llari. Jonli server ishlamayotganda
// kiosk klientini (oqim, filler, fallback, bekor qilish) sinash uchun.
//
// CLI:
//   /home/ucms/flutter-3.22.2/bin/dart run tool/mock_voice_server.dart --port 8787 --mode ok
//   flutter run -d linux --dart-define=KIOSK_API_ORIGIN=http://127.0.0.1:8787
//
// Rejim: --mode, yoki har so'rovda `X-Mock-Mode` sarlavhasi / `?mode=`:
//   ok         3 jumla: 1-say ~350 ms, keyingilari +400 ms, keyin done (jadval bilan)
//   slow       1-say ~1800 ms da (filler sinovi)
//   noaudio    say.audio = null (klient /tts/synthesize ga o'zi boradi)
//   404        chat-stream → 404 (eski server)
//   err-before {"t":"error"} birinchi say'dan OLDIN
//   err-mid    1 ta say, keyin {"t":"error"}
//   drop-mid   1 ta say, keyin oqim done'siz tugaydi
//   stall      sarlavha + ping, keyin jimlik (idle-timeout sinovi)
//   split      javob baytma-bayt (UTF-8 / qator bo'linishi sinovi)
//   persona    persona:true javob (2 jumla)
//   doneonly   say'siz faqat done (matn bilan)
//   empty      say'siz, bo'sh matnli done (klient "Kechirasiz..." deydi)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MockVoiceServer {
  MockVoiceServer._(this._server, this.mode, this._audioFor);

  final HttpServer _server;
  String mode;
  final Uint8List Function(String text) _audioFor;
  final Map<String, int> hits = {};
  int streamAborted = 0; // klient oqimni o'rtada yopgan holatlar
  final List<Map<String, dynamic>> streamBodies = [];

  /// /stt javoblari navbati (testlar uchun); bo'sh bo'lsa standart matn.
  final List<String> sttScript = [];

  /// Har /stt so'rovi: (mode parametri, tana hajmi baytda).
  final List<(String?, int)> sttRequests = [];

  int get port => _server.port;
  String get origin => 'http://127.0.0.1:$port';

  static Future<MockVoiceServer> start({
    int port = 0,
    String mode = 'ok',
    Uint8List Function(String text)? audioFor,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final m = MockVoiceServer._(server, mode, audioFor ?? fakeMp3);
    server.listen(m._handle);
    return m;
  }

  Future<void> close() => _server.close(force: true);

  /// Test uchun "mp3" — mazmuni ahamiyatsiz (FakeClipPlayer o'ynamaydi), ≥200 bayt.
  static Uint8List fakeMp3(String text) {
    final b = BytesBuilder()
      ..add([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 0])
      ..add(utf8.encode(text));
    while (b.length < 600) {
      b.addByte(0);
    }
    return b.toBytes();
  }

  static const _sentences = {
    'uz': [
      'Auksion yerlar: jami 19 649 ta.',
      'Eng ko‘pi — Qo‘rg‘ontepa tumanida, 1 812 ta.',
      'Batafsil ma’lumot ekranda.',
    ],
    'ru': [
      'Аукционных участков: всего 19 649.',
      'Больше всего — в Кургантепинском районе, 1 812.',
      'Подробности на экране.',
    ],
    'en': [
      'Auction plots: 19,649 in total.',
      'Most are in Qo‘rg‘ontepa district, 1,812.',
      'Details are on the screen.',
    ],
  };

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    final mode = req.headers.value('x-mock-mode') ?? req.uri.queryParameters['mode'] ?? this.mode;
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    try {
      switch (path) {
        case '/api/v1/health':
          return _json(res, {'ok': true, 'ts': DateTime.now().millisecondsSinceEpoch});
        case '/api/v1/ai/chat-stream':
          return await _chatStream(req, res, mode);
        case '/api/v1/ai/chat':
          final body = await _readJson(req);
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final lang = _lang(body['lang']);
          final s = _sentences[lang]!;
          return _json(res, {
            'text': s.join(' '),
            'table': [
              ['Qo‘rg‘ontepa tumani', 1812],
              ['Andijon tumani', 1730],
            ],
            'source': 'mock',
            'persona': mode == 'persona',
          });
        case '/api/v1/tts/synthesize':
          final text = req.uri.queryParameters['text'] ?? '';
          await Future<void>.delayed(const Duration(milliseconds: 120));
          final mp3 = _audioFor(text);
          res.headers.contentType = ContentType('audio', 'mpeg');
          res.contentLength = mp3.length;
          res.add(mp3);
          return await res.close();
        case '/api/v1/stt':
          var n = 0;
          await for (final chunk in req) {
            n += chunk.length;
          }
          sttRequests.add((req.uri.queryParameters['mode'], n));
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _json(res, {'text': sttScript.isNotEmpty ? sttScript.removeAt(0) : 'Alomat, auksion yerlar nechta'});
        case '/api/v1/ai/heard':
        case '/api/v1/kiosk/ping':
          await req.drain<void>();
          return _json(res, {'ok': true});
        case '/api/v1/avatar':
          return _json(res, {'enabled': false, 'voice': 'madina'});
        case '/api/v1/ai/warmup':
          return _json(res, {'loading': false});
        default:
          await req.drain<void>();
          res.statusCode = 404;
          return _json(res, {'error': 'unknown endpoint', 'path': path});
      }
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static String _lang(Object? l) => (l == 'ru' || l == 'en') ? l as String : 'uz';

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    if (raw.trim().isEmpty) return {};
    final v = jsonDecode(raw);
    return v is Map ? Map<String, dynamic>.from(v) : {};
  }

  Future<void> _json(HttpResponse res, Object body) async {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _chatStream(HttpRequest req, HttpResponse res, String mode) async {
    final body = await _readJson(req);
    streamBodies.add(body);
    if (mode == '404') {
      res.statusCode = 404;
      return _json(res, {'error': 'unknown endpoint', 'path': req.uri.path});
    }
    final lang = _lang(body['lang']);
    var sentences = List<String>.from(_sentences[lang]!);
    if (mode == 'persona') sentences = ['Mening ismim Alomat.', 'Sizga qanday yordam bera olaman?'];
    // Xom soket (chunked) — klient ulanishni uzganini ANIQ bilish uchun (HttpServer
    // yozish xatolarini yashiradi).
    final sock = await res.detachSocket(writeHeaders: false);
    var closed = false;
    sock.listen((_) {}, onDone: () {
      if (!closed) streamAborted++;
      closed = true;
    }, onError: (Object _) {
      if (!closed) streamAborted++;
      closed = true;
    });
    sock.write('HTTP/1.1 200 OK\r\n'
        'Content-Type: application/x-ndjson; charset=utf-8\r\n'
        'Cache-Control: no-store\r\n'
        'X-Accel-Buffering: no\r\n'
        'Access-Control-Allow-Origin: *\r\n'
        'Transfer-Encoding: chunked\r\n'
        'Connection: close\r\n\r\n');

    Future<bool> chunk(List<int> data) async {
      if (closed) return false;
      try {
        sock.add(ascii.encode('${data.length.toRadixString(16)}\r\n'));
        sock.add(data);
        sock.add(const [13, 10]);
        await sock.flush();
        return true;
      } catch (_) {
        if (!closed) streamAborted++;
        closed = true;
        return false;
      }
    }

    Future<bool> send(Map<String, dynamic> ev) async {
      final line = utf8.encode('${jsonEncode(ev)}\n');
      if (mode != 'split') return chunk(line);
      // baytma-bayt (ko'p baytli UTF-8 belgilar ham bo'linadi)
      for (var i = 0; i < line.length; i += 3) {
        if (!await chunk(line.sublist(i, i + 3 > line.length ? line.length : i + 3))) return false;
        await Future<void>.delayed(Duration.zero);
      }
      return true;
    }

    Future<void> end() async {
      if (closed) return;
      try {
        sock.add(ascii.encode('0\r\n\r\n'));
        await sock.flush();
      } catch (_) {}
      closed = true;
      try {
        await sock.close();
      } catch (_) {}
      sock.destroy();
    }

    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

    await send({'t': 'ping'});
    if (mode == 'stall') {
      for (var i = 0; i < 600 && !closed; i++) {
        await wait(100);
      }
      return end();
    }
    if (mode == 'err-before') {
      await wait(200);
      await send({'t': 'error', 'error': 'gemini timeout'});
      return end();
    }
    if (mode == 'empty') {
      await wait(150);
      await send({
        't': 'done',
        'out': {'text': '', 'source': 'mock'}
      });
      return end();
    }
    if (mode == 'doneonly') {
      await wait(200);
      await send({
        't': 'done',
        'out': {'text': sentences.join(' '), 'source': 'mock'}
      });
      return end();
    }
    await wait(mode == 'slow' ? 1800 : 350);
    for (var i = 0; i < sentences.length; i++) {
      if (i > 0) await wait(400);
      final audio = mode == 'noaudio' ? null : base64Encode(_audioFor(sentences[i]));
      if (!await send({'t': 'say', 'i': i, 'text': sentences[i], 'audio': audio})) return end();
      if (mode == 'err-mid') {
        await wait(100);
        await send({'t': 'error', 'error': 'tts failed'});
        return end();
      }
      if (mode == 'drop-mid') {
        await wait(100);
        return end(); // done'siz tugaydi (ulanish uzildi)
      }
    }
    await send({
      't': 'done',
      'out': {
        'text': sentences.join(' '),
        'table': mode == 'persona'
            ? null
            : [
                ['Qo‘rg‘ontepa tumani', 1812],
                ['Andijon tumani', 1730],
              ],
        'source': 'mock',
        'persona': mode == 'persona',
      }
    });
    await end();
  }
}

/// ffmpeg bo'lsa — matn uzunligiga mos haqiqiy MP3 (sinus ohang), aks holda soxta bayt.
Uint8List Function(String) _ffmpegAudio() {
  final cache = <String, Uint8List>{};
  return (text) {
    final hit = cache[text];
    if (hit != null) return hit;
    try {
      final dur = (0.4 + text.length * 0.055).clamp(0.5, 8.0).toStringAsFixed(2);
      final tmp = '${Directory.systemTemp.path}/mock_tts_${text.hashCode.toUnsigned(32)}.mp3';
      final r = Process.runSync('ffmpeg', [
        '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=$dur',
        '-ac', '1', '-ar', '24000', '-b:a', '48k', tmp,
      ]);
      if (r.exitCode == 0) {
        final b = File(tmp).readAsBytesSync();
        cache[text] = b;
        return b;
      }
    } catch (_) {}
    return cache[text] = MockVoiceServer.fakeMp3(text);
  };
}

Future<void> main(List<String> args) async {
  var port = 8787;
  var mode = 'ok';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) port = int.parse(args[++i]);
    if (args[i] == '--mode' && i + 1 < args.length) mode = args[++i];
  }
  final s = await MockVoiceServer.start(port: port, mode: mode, audioFor: _ffmpegAudio());
  stdout.writeln('mock voice server: ${s.origin}/api/v1  (mode=$mode)');
}
