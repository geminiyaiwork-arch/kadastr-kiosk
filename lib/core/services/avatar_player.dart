import 'package:flutter_riverpod/flutter_riverpod.dart';

/// JONLI AVATAR — VIDEO OLIB TASHLANGAN (Smart App Control `libmpv`/media_kit DLL'ni
/// bloklaydi: "Bad Image 0xc0e90002"). Bu STUB: avatar STATIK rasm sifatida ko'rsatiladi,
/// javob ovozi TTS (audioplayers) orqali chalinadi — lab-sinxron video yo'q.
/// Ommaviy API saqlangan (ai_screen/voice_controller o'zgarmaydi). Videoni qaytarish
/// kerak bo'lsa — media_kit'li asosiy `main` branch'dan oling (SAC o'chirilgan mashinada).
class AvatarPlayerState {
  final bool speaking;
  final bool idleReady;
  final int session;
  const AvatarPlayerState({this.speaking = false, this.idleReady = false, this.session = 0});
}

class AvatarPlayer extends StateNotifier<AvatarPlayerState> {
  AvatarPlayer(this.ref) : super(const AvatarPlayerState());
  final Ref ref;

  /// Video moduli yo'q — hech qachon qo'llab-quvvatlanmaydi (statik avatar + TTS).
  static bool get supported => false;

  Future<void> ensureIdle(dynamic av) async {}

  /// Lab-sinxron video yo'q → false qaytaradi (chaqiruvchi oddiy TTS'ga qaytadi).
  Future<bool> speak(dynamic av, String text, String lang, {String voice = 'madina'}) async => false;
}

final avatarPlayerProvider =
    StateNotifierProvider<AvatarPlayer, AvatarPlayerState>((ref) => AvatarPlayer(ref));
