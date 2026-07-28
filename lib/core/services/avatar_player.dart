import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player_win/video_player_win.dart';

import '../env.dart';

/// JONLI AVATAR — LAB-SINXRON VIDEO (Wav2Lip) generatsiya + o'ynatish.
/// Video motoru = `video_player_win` (Windows Media Foundation) — media_kit(libmpv)
/// O'RNIGA (libmpv DLL'ni Smart App Control bloklaydi; MF-asosli plagin SAC-xavfsiz,
/// zastavka/appeal/info ekranlarida allaqachon ishlaydi).
///
/// FAQAT MULOQAT (persona/salomlashuv) savollarida chaqiriladi — server `/avatar/speak`
/// mp4 qaytaradi (TTS ovozi ichida), kiosk uni to'liq ekranda o'ynatadi. Ma'lumotli
/// javoblarda video generatsiya QILINMAYDI (avatar burchakda statik + karta ko'rinadi,
/// javob TTS ovozida). Windows'dan tashqarida (Linux dev) yoki xatoда `false` qaytadi →
/// chaquruvchi oddiy TTS'ga tushadi.
class AvatarPlayerState {
  final bool speaking;
  final bool idleReady;
  final int session;
  final WinVideoPlayerController? controller;
  final WinVideoPlayerController? idleController; // jim-holat ko'z-pirpirash loop
  const AvatarPlayerState({
    this.speaking = false,
    this.idleReady = false,
    this.session = 0,
    this.controller,
    this.idleController,
  });

  AvatarPlayerState copyWith({
    bool? speaking,
    bool? idleReady,
    int? session,
    WinVideoPlayerController? controller,
    WinVideoPlayerController? idleController,
    bool clearController = false,
    bool clearIdle = false,
  }) =>
      AvatarPlayerState(
        speaking: speaking ?? this.speaking,
        idleReady: idleReady ?? this.idleReady,
        session: session ?? this.session,
        controller: clearController ? null : (controller ?? this.controller),
        idleController: clearIdle ? null : (idleController ?? this.idleController),
      );
}

class AvatarPlayer extends StateNotifier<AvatarPlayerState> {
  AvatarPlayer(this.ref) : super(const AvatarPlayerState());
  final Ref ref;
  final _dio = Dio();
  int _seq = 0;
  Directory? _cacheDir;
  Completer<void>? _cancel; // joriy o'ynayotgan videoni tez bekor qilish uchun

  /// Video faqat Windows kioskда (video_player_win = Windows Media Foundation).
  static bool get supported => Platform.isWindows;

  int _idleTs = -1;
  bool _idleBusy = false;

  /// JIM-HOLAT ko'z-pirpirash idle-VIDEOSINI (server rasmdan avto-yasagan) yuklab, LOOP
  /// qiladi (ovozsiz). Bir marta tayyorlanadi; admin yangi avatar qo'ysa (idleVideoTs
  /// o'zgarsa) qayta yuklanadi. Windows'dan tashqarida no-op.
  Future<void> ensureIdle(dynamic av) async {
    if (!Platform.isWindows || av == null) return;
    final String idleVideo = (av.idleVideo ?? '').toString();
    final int ts = (av.idleVideoTs ?? 0) as int;
    if (idleVideo.isEmpty) return;
    if (state.idleController != null && _idleTs == ts) return; // allaqachon tayyor
    if (_idleBusy) return;
    _idleBusy = true;
    WinVideoPlayerController? c;
    try {
      final dir = await _dir();
      final f = File('${dir.path}${Platform.pathSeparator}idle_$ts.mp4');
      if (!await f.exists() || (await f.length()) < 1000) {
        final resp = await _dio.get<List<int>>(
          '${Env.apiBase}/avatar/idle-video',
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 30)),
        );
        final bytes = resp.data ?? const <int>[];
        if (bytes.length < 1000) return;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        try {
          await tmp.rename(f.path);
        } catch (_) {}
      }
      final playFile = await f.exists() ? f : File('${f.path}.tmp');
      c = WinVideoPlayerController.file(playFile);
      await c.initialize().timeout(const Duration(seconds: 8));
      if (!c.value.isInitialized) {
        try { await c.dispose(); } catch (_) {}
        return;
      }
      await c.setLooping(true);
      await c.setVolume(0); // jim-holat — ovozsiz
      if (!state.speaking) await c.play(); // gapirmayotgan bo'lsa darhol o'ynatamiz
      final old = state.idleController;
      _idleTs = ts;
      state = state.copyWith(idleController: c, idleReady: true);
      if (old != null) { try { await old.dispose(); } catch (_) {} }
      c = null; // state egalik qiladi — finally dispose qilmasin
    } catch (_) {
      // xato — jimда statik rasm qoladi (regress yo'q)
    } finally {
      if (c != null) { try { await c.dispose(); } catch (_) {} }
      _idleBusy = false;
    }
  }

  /// JORIY o'ynayotgan avatar-videoni DARHOL to'xtatadi (foydalanuvchi yangi savol
  /// bersa/mikrofon bossa — ovoz ustma-ust tushmasin, burchakда eski video qolmasin).
  /// Controller o'zining speak() `finally` blokida bir marta dispose qilinadi (double-dispose yo'q).
  Future<void> stop() async {
    _seq++; // joriy va kutilayotgan speak()larni eskirtiradi
    final cc = _cancel;
    if (cc != null && !cc.isCompleted) cc.complete(); // speak()dagi Future.any darhol chiqadi
    final c = state.controller;
    if (c != null) {
      try {
        await c.pause(); // ovoz darhol jim (dispose speak() finally'да)
      } catch (_) {}
    }
    if (c != null || state.speaking) {
      state = state.copyWith(speaking: false, clearController: true);
    }
    // Jim-holat ko'z-pirpirash loop qaytadi (gapirish to'xtadi).
    try {
      final ic = state.idleController;
      if (ic != null && ic.value.isInitialized && !ic.value.isPlaying) await ic.play();
    } catch (_) {}
  }

  // FNV-1a 32-bit — BARQAROR kesh-fayl nomi (String.hashCode run'lar aro kafolatlanmagan,
  // takror savol keshini buzardi).
  String _hash(String s) {
    int h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}lipsync');
    if (!await d.exists()) await d.create(recursive: true);
    _cacheDir = d;
    return d;
  }

  /// Muloqat javobini lab-sinxron video bilan gapiradi. Muvaffaqiyatда `true`
  /// (TTS chalinmaydi — ovoz video ichida); Windows emas / xato / bo'sh fayl → `false`.
  Future<bool> speak(dynamic av, String text, String lang, {String voice = 'madina'}) async {
    if (!Platform.isWindows) return false;
    final clean = text.trim();
    if (clean.isEmpty) return false;
    final say = clean.length > 800 ? clean.substring(0, 800) : clean;
    // oldingi videoni bekor qilamiz + shu speak uchun yangi cancel-signali
    final prev = _cancel;
    if (prev != null && !prev.isCompleted) prev.complete();
    final cancel = _cancel = Completer<void>();
    final mySeq = ++_seq;
    WinVideoPlayerController? c;
    try {
      // 1) LOKAL KESH — takror muloqat (salom/persona) qayta yuklab olinmaydi.
      //    (Server ham disk-keshlaydi → birinchi safar ham tez.)
      final dir = await _dir();
      final key = _hash('$voice|$lang|$say');
      final file = File('${dir.path}${Platform.pathSeparator}$key.mp4');
      if (!await file.exists() || (await file.length()) < 1000) {
        final url = '${Env.apiBase}/avatar/speak'
            '?text=${Uri.encodeQueryComponent(say)}&lang=$lang&voice=$voice';
        final resp = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 15),
          ),
        );
        final bytes = resp.data ?? const <int>[];
        if (bytes.length < 1000) return false; // server bo'sh/xato → TTS
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        try {
          await tmp.rename(file.path);
        } catch (_) {
          // rename muvaffaqiyatsiz bo'lsa tmp'ni to'g'ridan-to'g'ri o'ynatamiz
        }
      }
      if (mySeq != _seq) return true; // yangi savol keldi — bu videoni jimgina tashlaymiz

      // 2) O'YNATISH
      final playFile = await file.exists() ? file : File('${file.path}.tmp');
      c = WinVideoPlayerController.file(playFile);
      await c.initialize().timeout(const Duration(seconds: 8));
      if (mySeq != _seq || !c.value.isInitialized) {
        try {
          await c.dispose();
        } catch (_) {}
        return c.value.isInitialized; // eskirgan bo'lsa "bajarildi" deb hisoblaymiz
      }
      await c.setVolume(1.0);
      try { await state.idleController?.pause(); } catch (_) {} // gapirganda idle loop pauza
      state = state.copyWith(speaking: true, controller: c, session: state.session + 1);
      await c.play();

      // Tugashini kutamiz (position→duration) yoki cap-vaqt (backstop) yoki BEKOR (stop()).
      final dur = c.value.duration;
      // clamp: metadata yo'q bo'lsa ham 20s dan oshmasin (persona javoblari qisqa).
      final rawCap = dur.inMilliseconds > 0 ? dur.inMilliseconds + 1500 : 12000;
      final capMs = rawCap < 2000 ? 2000 : (rawCap > 20000 ? 20000 : rawCap);
      final done = Completer<void>();
      final ctrl = c;
      void listener() {
        final v = ctrl.value;
        if (!v.isInitialized) return;
        final d = v.duration;
        // tugadi: position→duration YOKI o'ynash to'xtab, boshidan nariga o'tган (WMF ended)
        final ended = (d.inMilliseconds > 0 && v.position >= d - const Duration(milliseconds: 140)) ||
            (!v.isPlaying && v.position > const Duration(milliseconds: 300) && v.position >= d - const Duration(milliseconds: 350));
        if (ended && !done.isCompleted) done.complete();
      }

      c.addListener(listener);
      await Future.any<void>([done.future, cancel.future, Future<void>.delayed(Duration(milliseconds: capMs))]);
      c.removeListener(listener);
      return true;
    } catch (_) {
      return false; // har qanday xato → oddiy TTS fallback
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      // FAQAT shu sessiya controllerini state'dan olib tashlaymiz (yangisi qo'yilgan bo'lishi mumkin).
      if (c != null && identical(state.controller, c)) {
        state = state.copyWith(speaking: false, clearController: true);
      }
      try {
        await c?.pause();
      } catch (_) {}
      try {
        await c?.dispose();
      } catch (_) {}
      // Gapirib bo'lgach jim-holat ko'z-pirpirash loop QAYTADI (agar boshqa savol kelmagan bo'lsa).
      if (mySeq == _seq && !state.speaking) {
        try {
          final ic = state.idleController;
          if (ic != null && ic.value.isInitialized && !ic.value.isPlaying) await ic.play();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    try { state.idleController?.dispose(); } catch (_) {}
    super.dispose();
  }
}

final avatarPlayerProvider =
    StateNotifierProvider<AvatarPlayer, AvatarPlayerState>((ref) => AvatarPlayer(ref));
