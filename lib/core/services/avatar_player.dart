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
  const AvatarPlayerState({
    this.speaking = false,
    this.idleReady = false,
    this.session = 0,
    this.controller,
  });

  AvatarPlayerState copyWith({
    bool? speaking,
    bool? idleReady,
    int? session,
    WinVideoPlayerController? controller,
    bool clearController = false,
  }) =>
      AvatarPlayerState(
        speaking: speaking ?? this.speaking,
        idleReady: idleReady ?? this.idleReady,
        session: session ?? this.session,
        controller: clearController ? null : (controller ?? this.controller),
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

  Future<void> ensureIdle(dynamic av) async {}

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
    }
  }
}

final avatarPlayerProvider =
    StateNotifierProvider<AvatarPlayer, AvatarPlayerState>((ref) => AvatarPlayer(ref));
