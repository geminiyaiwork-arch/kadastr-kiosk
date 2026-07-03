import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../network/api_client.dart';
import '../network/models.dart';

/// JONLI AVATAR pleeri (media_kit):
///  - BO'SH holat: avatar VIDEOsi aylanib turadi (kiprik qoqish, qo'l harakati —
///    manba videodagi tabiiy harakatlar), ovozsiz loop.
///  - GAPIRISH: server /avatar/speak (TTS + Wav2Lip) dan LAB-SINXRON mp4 olinadi
///    va ovozi bilan o'sha oynada o'ynatiladi — so'zga mos lab qimirlaydi.
/// Video tayyor bo'lmasa UI eski usulga (rasm + audio) o'zi qaytadi.
class AvatarPlayerState {
  final bool ready; // idle video yuklab bo'lindi — Video widget ko'rsatsa bo'ladi
  final bool speaking; // hozir lab-sinx klip o'ynayapti
  const AvatarPlayerState({this.ready = false, this.speaking = false});
  AvatarPlayerState copyWith({bool? ready, bool? speaking}) =>
      AvatarPlayerState(ready: ready ?? this.ready, speaking: speaking ?? this.speaking);
}

class AvatarPlayer extends StateNotifier<AvatarPlayerState> {
  AvatarPlayer(this.ref) : super(const AvatarPlayerState());
  final Ref ref;

  Player? _player;
  VideoController? controller;
  String? _idlePath;
  bool _downloading = false;

  Dio get _dio => ref.read(dioProvider);

  /// Barqaror kesh papka (restartda 36MB video qayta yuklanmasin).
  Directory _cacheDir() {
    final home = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return Directory('$home/.kadastr_kiosk_cache');
  }

  Player _ensurePlayer() {
    if (_player != null) return _player!;
    final p = Player();
    _player = p;
    controller = VideoController(p);
    return p;
  }

  /// JONLI avatar qayerda yoqiq: Windows (media_kit o'z libmpv'sini oladi — barqaror).
  /// Linux'da tizim libmpv'siga bog'liq — juda yangi versiyalar (0.41, Kali) bilan
  /// media_kit QULAYDI (jonli sinovda 3 rejimda ham segfault) -> standartda O'CHIQ,
  /// KAI_LIVE_AVATAR=1 env bilan yoqsa bo'ladi (mos distroda). Fallback: rasm + ovoz.
  static bool get supported =>
      Platform.isWindows || Platform.environment['KAI_LIVE_AVATAR'] == '1';

  /// Avatar VIDEOsini bir marta yuklab (ts bo'yicha kesh), ovozsiz loop qilib qo'yadi.
  Future<void> ensureIdle(AvatarConfig av) async {
    if (!supported) return;
    if (!av.enabled || av.type != 'video' || _downloading) return;
    if (state.ready && _idlePath != null) return;
    _downloading = true;
    try {
      final dir = _cacheDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/avatar_${av.ts}.mp4');
      if (!f.existsSync() || f.lengthSync() < 100000) {
        final r = await _dio.get<List<int>>(
          '/avatar/file',
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 3)),
        );
        final bytes = r.data ?? const <int>[];
        if (bytes.length < 100000) throw Exception('avatar video juda kichik');
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        tmp.renameSync(f.path);
        // eski versiya keshlari tozalanadi
        for (final e in dir.listSync()) {
          if (e is File && e.path.contains('avatar_') && e.path != f.path) {
            try { e.deleteSync(); } catch (_) {}
          }
        }
      }
      _idlePath = f.path;
      final p = _ensurePlayer();
      await p.setVolume(0);
      await _mpvLoop(p, true);   // mpv'ning O'Z loop'i — video hech qachon "tugamaydi"
      await p.open(Media(f.path), play: true);
      state = state.copyWith(ready: true);
      // ignore: avoid_print
      print('[avatar] idle video ochildi: ${f.path}');
    } catch (e) {
      // ignore: avoid_print
      print('[avatar] ensureIdle xato: $e');
    } finally {
      _downloading = false;
    }
  }

  /// mpv'ning ichki loop'i (loop-file=inf): media_kit'ning playlist-restart yo'lini
  /// CHETLAB o'tadi — Linux'da yangi libmpv bilan o'sha yo'l segfault berardi
  /// (qulashlar doim video OXIRIDA edi). Native bo'lmasa jim o'tadi.
  Future<void> _mpvLoop(Player p, bool on) async {
    try {
      final plat = p.platform;
      // NativePlayer.setProperty — media_kit 1.x
      // ignore: avoid_dynamic_calls
      await (plat as dynamic).setProperty('loop-file', on ? 'inf' : 'no');
    } catch (_) {}
  }

  /// LAB-SINXRON gapirish: /avatar/speak dan mp4 olib, ovozi bilan o'ynatadi.
  /// Muvaffaqiyatda true (audio ham video ichida — alohida TTS chalinmasin).
  Future<bool> speak(String text, String lang, {String voice = 'madina'}) async {
    if (!state.ready || _idlePath == null) return false;
    File? clip;
    try {
      final r = await _dio.get<List<int>>(
        '/avatar/speak',
        queryParameters: {'text': text, 'lang': lang, 'voice': voice},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 40)),
      );
      final bytes = r.data ?? const <int>[];
      if (bytes.length < 20000) return false; // xato/bo'sh javob
      clip = File('${Directory.systemTemp.path}/kai_speak_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await clip.writeAsBytes(bytes, flush: true);

      final p = _ensurePlayer();
      state = state.copyWith(speaking: true);
      await _mpvLoop(p, false);   // klip BIR marta o'ynaydi
      await p.setVolume(100);
      final done = p.stream.completed.firstWhere((c) => c).timeout(
            Duration(seconds: 20 + text.length ~/ 8),
            onTimeout: () => true,
          );
      await p.open(Media(clip.path), play: true);
      await done;
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[avatar] speak xato: $e');
      return false;
    } finally {
      state = state.copyWith(speaking: false);
      // orqaga: bo'sh-holat loopi (ovozsiz, mpv-native loop)
      try {
        final p = _ensurePlayer();
        await p.setVolume(0);
        await _mpvLoop(p, true);
        if (_idlePath != null) await p.open(Media(_idlePath!), play: true);
      } catch (_) {}
      try { clip?.deleteSync(); } catch (_) {}
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}

final avatarPlayerProvider =
    StateNotifierProvider<AvatarPlayer, AvatarPlayerState>((ref) => AvatarPlayer(ref));
