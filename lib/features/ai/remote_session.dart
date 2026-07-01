import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/network/api_client.dart';
import 'voice_controller.dart';

class RemoteState {
  final String token;
  final bool connected;
  const RemoteState({this.token = '', this.connected = false});
  RemoteState copyWith({String? token, bool? connected}) =>
      RemoteState(token: token ?? this.token, connected: connected ?? this.connected);
}

/// Telefon ovozli pult: kiosk burchakda QR ko'rsatadi (token bilan). Telefon shu
/// sahifani ochib gapiradi → matn server "voice bus" orqali keladi → VoiceController
/// bajaradi (navigatsiya / AI javob + ovoz). Telefon ulanganda QR yashirinadi.
class RemoteSession extends StateNotifier<RemoteState> {
  RemoteSession(this.ref) : super(const RemoteState()) {
    state = RemoteState(token: _genTok());
    _on = true;
    _loop();
  }
  final Ref ref;
  bool _on = false;
  Timer? _idle;

  Dio get _dio => ref.read(dioProvider);

  String _genTok() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Telefon ochadigan sahifa — portal domeni (api emas).
  String get phoneUrl {
    final origin = Env.apiOrigin.replaceFirst('://api.', '://');
    return '$origin/voice.html?s=${state.token}';
  }

  Future<void> _loop() async {
    while (_on) {
      try {
        final r = await _dio.get(
          '/voice/poll',
          queryParameters: {'s': state.token},
          options: Options(receiveTimeout: const Duration(seconds: 30)), // long-poll (server ~25s ushlaydi)
        );
        final m = Map<String, dynamic>.from(r.data as Map);
        if (m['hello'] == true) {
          _markConnected();
        } else if (m['text'] != null && '${m['text']}'.trim().isNotEmpty) {
          _markConnected();
          await ref.read(voiceProvider.notifier).handleRemoteText('${m['text']}'.trim());
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  void _markConnected() {
    if (!state.connected) state = state.copyWith(connected: true);
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 75), () {
      if (mounted) state = state.copyWith(connected: false); // jim qolsa QR qaytadi
    });
  }

  @override
  void dispose() {
    _on = false;
    _idle?.cancel();
    super.dispose();
  }
}

final remoteSessionProvider =
    StateNotifierProvider<RemoteSession, RemoteState>((ref) => RemoteSession(ref));
