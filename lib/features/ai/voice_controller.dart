import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/env.dart';
import '../../core/network/api_client.dart';
import '../../core/network/repository.dart';

enum VoicePhase { off, listening, transcribing, thinking, speaking }

class VoiceUiState {
  final VoicePhase phase;
  final String heard;
  final String answer;
  final List<List<dynamic>>? table;
  final bool speaking;
  final String? error;
  const VoiceUiState({
    this.phase = VoicePhase.off,
    this.heard = '',
    this.answer = '',
    this.table,
    this.speaking = false,
    this.error,
  });

  VoiceUiState copyWith({VoicePhase? phase, String? heard, String? answer, List<List<dynamic>>? table, bool? speaking, String? error, bool clearError = false}) =>
      VoiceUiState(
        phase: phase ?? this.phase,
        heard: heard ?? this.heard,
        answer: answer ?? this.answer,
        table: table ?? this.table,
        speaking: speaking ?? this.speaking,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Wake-word variants for "KAI" (= Kadastr AI), incl. Whisper mis-hearings.
const _wakeSet = {
  'kai', 'kayi', 'kay', 'kei', 'key', 'kaye', 'qay', 'qai', 'qei', 'kayy', 'kae',
  'кай', 'кей', 'кайи', 'кад', 'kadastr', 'cadastre',
};

/// Single always-on voice engine: mic → VAD → /stt → wake-route → /ai/chat → TTS.
/// Runs globally; on the AI page the wake word is optional.
class VoiceController extends StateNotifier<VoiceUiState> {
  VoiceController(this.ref) : super(const VoiceUiState());
  final Ref ref;
  final _rec = AudioRecorder();
  final _player = AudioPlayer();

  bool _on = false;
  bool _busy = false;
  String _lang = 'uz';

  bool Function()? onAiPage; // direct mode (no wake needed)
  bool Function()? canListen; // false on the appeal page (camera owns the mic)
  void Function()? navToAi;

  Dio get _dio => ref.read(dioProvider);
  Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));
  void setLang(String lang) => _lang = lang;

  Future<void> startAmbient({
    required String lang,
    required bool Function() onAiPage,
    required bool Function() canListen,
    required void Function() navToAi,
  }) async {
    this.onAiPage = onAiPage;
    this.canListen = canListen;
    this.navToAi = navToAi;
    _lang = lang;
    if (_on) return;
    try {
      if (!await _rec.hasPermission()) {
        state = state.copyWith(error: 'mic');
        return;
      }
    } catch (_) {
      state = state.copyWith(error: 'mic');
      return;
    }
    _on = true;
    state = state.copyWith(phase: VoicePhase.listening, clearError: true);
    _loop();
  }

  Future<void> stop() async {
    _on = false;
    _busy = false;
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    state = state.copyWith(phase: VoicePhase.off, speaking: false);
  }

  /// Speak a greeting / prompt (used when entering the AI page or on wake-only).
  Future<void> greet(String text) async {
    if (_busy) return;
    _busy = true;
    await _speak(text);
  }

  Future<void> _loop() async {
    while (_on) {
      if (_busy) {
        await _sleep(200);
        continue;
      }
      if (canListen != null && !canListen!()) {
        await _sleep(300); // appeal page — mic handed to the camera
        continue;
      }
      if (state.phase != VoicePhase.listening) state = state.copyWith(phase: VoicePhase.listening);
      final path = await _capture();
      if (!_on) break;
      if (path == null) continue;
      _busy = true;
      state = state.copyWith(phase: VoicePhase.transcribing);
      final text = await _stt(path);
      if (text != null && text.isNotEmpty && _valid(text)) {
        await _handle(text);
      } else {
        _busy = false;
      }
    }
  }

  Future<String?> _capture() async {
    final path = '${Directory.systemTemp.path}/kadastr_utt.wav';
    try {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    } catch (_) {
      await _sleep(500);
      return null;
    }
    var waited = 0;
    while (_on && !_busy) {
      final db = await _amp();
      if (db > Env.onsetDb) break;
      await _sleep(Env.onsetPollMs);
      waited += Env.onsetPollMs;
      if (waited > Env.onsetTimeoutMs) {
        await _stopRec();
        return null;
      }
    }
    if (!_on) {
      await _stopRec();
      return null;
    }
    var silence = 0, voiced = 0;
    final start = DateTime.now();
    while (_on) {
      await _sleep(Env.endPollMs);
      final db = await _amp();
      if (db < Env.stopDb) {
        silence += Env.endPollMs;
      } else {
        silence = 0;
        if (db > Env.onsetDb) voiced += Env.endPollMs;
      }
      if (silence > Env.endSilenceMs) break;
      if (DateTime.now().difference(start).inMilliseconds > Env.utteranceMaxMs) break;
    }
    await _stopRec();
    if (voiced < Env.minVoicedMs) return null;
    return path;
  }

  Future<double> _amp() async {
    try {
      return (await _rec.getAmplitude()).current;
    } catch (_) {
      return -160;
    }
  }

  Future<void> _stopRec() async {
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
  }

  Future<String?> _stt(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 1500) return null;
      final r = await _dio.post(
        '/stt',
        queryParameters: {'lang': _lang},
        data: Stream.fromIterable(bytes.map((b) => [b])),
        options: Options(contentType: 'application/octet-stream', headers: {Headers.contentLengthHeader: bytes.length}),
      );
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['error'] != null) return null;
      return (m['text'] ?? '').toString().trim();
    } catch (_) {
      return null;
    }
  }

  bool _valid(String text) {
    final s = text.replaceAll(RegExp(r'[.,!?\s\d]'), '');
    if (s.length < 2) return false;
    final latin = RegExp(r'[A-Za-zÀ-ɏʻ‘’]').allMatches(text).length;
    final cyr = RegExp(r'[Ѐ-ӿ]').allMatches(text).length;
    final foreign = RegExp(r'[؀-ۿऀ-ॿঀ-৿฀-๿぀-ヿ一-鿿가-힯]').allMatches(text).length;
    final good = _lang == 'ru' ? cyr : (latin + cyr);
    return good >= 2 && foreign <= good;
  }

  /// Find wake word in the first 3 tokens. null=no wake, ''=wake only, 'cmd'=wake+command.
  String? _stripWake(String text) {
    final low = text.toLowerCase().replaceAll(RegExp(r"['’`ʻʼ.,!?:;]"), '').trim();
    if (low.isEmpty) return null;
    final words = low.split(RegExp(r'\s+'));
    var wi = -1;
    for (var i = 0; i < min(3, words.length); i++) {
      final w = words[i];
      if (_wakeSet.contains(w) || w.startsWith('kadastr') || w.startsWith('cadastre')) {
        wi = i;
        break;
      }
    }
    if (wi < 0) return null;
    return words.sublist(wi + 1).join(' ').replaceAll(RegExp(r'^[\s,.:;!?"()\-—]+'), '').trim();
  }

  Future<void> _handle(String text) async {
    state = state.copyWith(heard: text);
    _logHeard(text);
    final onAi = onAiPage?.call() ?? false;
    if (onAi) {
      if (text.trim().length >= 6) {
        await askAI(text);
      } else {
        _busy = false;
      }
      return;
    }
    final cmd = _stripWake(text);
    if (cmd == null) {
      _busy = false; // no wake word — ignore
      return;
    }
    navToAi?.call();
    await _sleep(300);
    if (cmd.length >= 2) {
      await askAI(cmd);
    } else {
      await _speak(_prompt());
    }
  }

  Future<void> askAI(String q) async {
    _busy = true;
    state = state.copyWith(phase: VoicePhase.thinking);
    String answer = '';
    List<List<dynamic>>? table;
    try {
      final r = await _dio.post('/ai/chat', data: {'q': q, 'lang': _lang});
      final m = Map<String, dynamic>.from(r.data as Map);
      answer = (m['text'] ?? '').toString();
      if (m['table'] is List && (m['table'] as List).isNotEmpty) {
        table = (m['table'] as List).map((e) => (e as List).cast<dynamic>()).toList();
      }
    } catch (_) {}
    if (answer.trim().isEmpty) answer = _fallback();
    state = state.copyWith(answer: answer, table: table);
    await _speak(answer);
  }

  String _fallback() => {
        'uz': 'Kechirasiz, hozir javob bera olmadim. Iltimos, qaytadan ayting.',
        'ru': 'Извините, сейчас не смог ответить. Пожалуйста, повторите.',
        'en': 'Sorry, I could not answer right now. Please try again.',
      }[_lang]!;

  String _prompt() => {
        'uz': 'Eshitaman, savolingizni ayting.',
        'ru': 'Слушаю, задайте вопрос.',
        'en': 'I am listening, ask your question.',
      }[_lang]!;

  Future<void> _speak(String text) async {
    final clean = text.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) {
      _busy = false;
      return;
    }
    final voice = (ref.read(avatarProvider).valueOrNull?.male ?? false) ? 'sardor' : 'madina';
    final url = '${Env.apiBase}/tts/synthesize?text=${Uri.encodeComponent(clean.substring(0, min(clean.length, 800)))}'
        '&voice=$voice&lang=$_lang';
    state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
    try {
      await _player.stop();
      final done = _player.onPlayerComplete.first.timeout(const Duration(seconds: 30), onTimeout: () {});
      await _player.play(UrlSource(url));
      await done;
    } catch (_) {}
    state = state.copyWith(speaking: false);
    _busy = false;
  }

  void _logHeard(String text) {
    _dio.post('/ai/heard', data: {'text': text, 'lang': _lang, 'acted': true}).then((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _on = false;
    _rec.dispose();
    _player.dispose();
    super.dispose();
  }
}

final voiceProvider = StateNotifierProvider<VoiceController, VoiceUiState>((ref) => VoiceController(ref));
