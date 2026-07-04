import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../network/api_client.dart';
import '../network/models.dart';

/// JONLI AVATAR — foydalanuvchi talab qilgan oqim:
///   JIM turganda  -> oddiy avatar RASMI (UI'dagi Image, bu servis aralashmaydi)
///   GAPIRGANDA    -> server /avatar/speak (TTS + Wav2Lip) dan LAB-SINXRON mp4
///                    generatsiya qilinadi va o'sha klip ovozи bilan o'ynatiladi.
/// Har klip uchun YANGI pleer ochilib, tugashi bilan DARHOL yopiladi — uzun yashovchi
/// video-sessiya yo'q (Linux'da libmpv'ning uzun loop'dagi segfault'idan qochish).
/// Klip bo'lmasa/xato bo'lsa chaqiruvchi oddiy TTS'ga o'zi qaytadi.
class AvatarPlayerState {
  final bool speaking; // hozir lab-sinx klip o'ynayapti (UI video ko'rsatadi)
  final bool idleReady; // jim-holat video-loop tayyor (imo-ishora/kiprik)
  final int session; // controller almashganda UI yangilansin
  const AvatarPlayerState({this.speaking = false, this.idleReady = false, this.session = 0});
}

class AvatarPlayer extends StateNotifier<AvatarPlayerState> {
  AvatarPlayer(this.ref) : super(const AvatarPlayerState());
  final Ref ref;

  Player? _player;
  VideoController? controller;
  Player? _idlePlayer;
  VideoController? idleController;
  bool _busy = false;
  bool _idleBusy = false;

  Dio get _dio => ref.read(dioProvider);

  /// Barqaror kesh papka (restartda 36MB video qayta yuklanmasin).
  Directory _cacheDir() {
    final home = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return Directory('$home/.kadastr_kiosk_cache');
  }

  /// JIM-HOLAT video-loop: avatar manba-videosi (imo-ishora, kiprik) aylanib turadi.
  /// mpv'ning O'Z loop'i (loop-file=inf) — media_kit restart-yo'li chetlab o'tiladi.
  Future<void> ensureIdle(AvatarConfig? av) async {
    if (!supported || av == null || !av.enabled || av.type != 'video') return;
    if (state.idleReady || _idleBusy) return;
    _idleBusy = true;
    try {
      final dir = _cacheDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/avatar_${av.ts}.mp4');
      if (!f.existsSync() || f.lengthSync() < 100000) {
        final r = await _dio.get<List<int>>('/avatar/file',
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 3)));
        final bytes = r.data ?? const <int>[];
        if (bytes.length < 100000) throw Exception('avatar video kichik');
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        tmp.renameSync(f.path);
        for (final e in dir.listSync()) {
          if (e is File && e.path.contains('avatar_') && e.path != f.path) {
            try { e.deleteSync(); } catch (_) {}
          }
        }
      }
      final p = Player();
      _idlePlayer = p;
      idleController = VideoController(p);
      await p.setVolume(0);
      try {
        // ignore: avoid_dynamic_calls
        await (p.platform as dynamic).setProperty('loop-file', 'inf');
      } catch (_) {}
      await p.open(Media(f.path), play: true);
      state = AvatarPlayerState(speaking: state.speaking, idleReady: true, session: state.session + 1);
      _report('idle-loop ok');
    } catch (e) {
      _report('idle xato: $e');
    } finally {
      _idleBusy = false;
    }
  }

  /// LAB-SINXRON gapirish: mp4 generatsiya -> yangi pleer -> o'ynatish -> yopish.
  /// Muvaffaqiyatda true (audio klip ichida — alohida TTS chalinmasin).
  /// Qayerda yoqiq: Windows (D3D — barqaror). Linux'da Mesa-gallium (yangi versiyalari)
  /// Flutter GL bilan segfault beradi (coredump'da tasdiqlangan — video'siz ham) ->
  /// video-tekstura yukини qo'shmaymiz; KAI_LIVE_AVATAR=1 bilan majburan yoqsa bo'ladi.
  static bool get supported =>
      Platform.isWindows || Platform.environment['KAI_LIVE_AVATAR'] == '1';

  final Set<String> _reportedOnce = {};
  void _reportOnce(String why) {
    if (_reportedOnce.add(why)) _report('otkazildi: $why');
  }

  Future<bool> speak(AvatarConfig? av, String text, String lang, {String voice = 'madina'}) async {
    if (!supported) { _reportOnce('gate-linux'); return false; }
    if (av == null) { _reportOnce('konfig-null'); return false; }
    if (!av.enabled || av.type != 'video') { _reportOnce('enabled=${av.enabled} type=${av.type}'); return false; }
    if (_busy) return false;
    _busy = true;
    File? clip;
    Player? p;
    try {
      // speaking DARHOL yonadi (yuklashdan OLDIN) — UI avatar to'liq ekranda qoladi,
      // "javob-karta chiqib, keyin video, keyin yana karta" lipillashi bo'lmaydi
      state = AvatarPlayerState(speaking: true, idleReady: state.idleReady, session: state.session + 1);
      final r = await _dio.get<List<int>>(
        '/avatar/speak',
        queryParameters: {'text': text, 'lang': lang, 'voice': voice},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 40)),
      );
      final bytes = r.data ?? const <int>[];
      if (bytes.length < 20000) return false; // xato/bo'sh javob
      clip = File('${Directory.systemTemp.path}/kai_speak_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await clip.writeAsBytes(bytes, flush: true);

      p = Player();
      _player = p;
      controller = VideoController(p);
      state = AvatarPlayerState(speaking: true, idleReady: state.idleReady, session: state.session + 1);
      await p.setVolume(100);
      // birinchi kadr chiqishiga oz vaqt — UI video'ga silliq almashadi
      final done = p.stream.completed.firstWhere((c) => c).timeout(
            Duration(seconds: 25 + text.length ~/ 8),
            onTimeout: () => true,
          );
      await p.open(Media(clip.path), play: true);
      await done;
      _report('video ok (${bytes.length ~/ 1024}KB)');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[avatar] speak xato: $e');
      _report('xato: $e');
      return false;
    } finally {
      state = AvatarPlayerState(speaking: false, idleReady: state.idleReady, session: state.session + 1);
      controller = null;
      try { await p?.dispose(); } catch (_) {}
      if (identical(_player, p)) _player = null;
      try { clip?.deleteSync(); } catch (_) {}
      _busy = false;
    }
  }

  /// Masofaviy diagnostika: Windows kioskda konsol yo'q — natija admin "AI log"ida
  /// ko'rinadi (/ai/heard). Xatoga chidamli, javob kutilmaydi.
  void _report(String msg) {
    try {
      _dio.post('/ai/heard', data: {'text': '[avatar] $msg', 'lang': 'uz', 'acted': false})
          .then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    try { _player?.dispose(); } catch (_) {}
    try { _idlePlayer?.dispose(); } catch (_) {}
    super.dispose();
  }
}

final avatarPlayerProvider =
    StateNotifierProvider<AvatarPlayer, AvatarPlayerState>((ref) => AvatarPlayer(ref));
