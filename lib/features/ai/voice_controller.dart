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
  final bool recording; // tap-to-talk: qo'lda yozilyapti
  final String? error;
  const VoiceUiState({
    this.phase = VoicePhase.off,
    this.heard = '',
    this.answer = '',
    this.table,
    this.speaking = false,
    this.recording = false,
    this.error,
  });

  VoiceUiState copyWith({VoicePhase? phase, String? heard, String? answer, List<List<dynamic>>? table, bool? speaking, bool? recording, String? error, bool clearError = false}) =>
      VoiceUiState(
        phase: phase ?? this.phase,
        heard: heard ?? this.heard,
        answer: answer ?? this.answer,
        table: table ?? this.table,
        speaking: speaking ?? this.speaking,
        recording: recording ?? this.recording,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Wake-word variants for "KAI" (= Kadastr AI), incl. Whisper mis-hearings.
const _wakeSet = {
  'kai', 'kayi', 'kay', 'kei', 'key', 'kaye', 'qay', 'qai', 'qei', 'qey', 'qiy', 'qyi',
  'kayy', 'kae', 'kya', 'kyi', 'gay', 'gey', 'gai', 'kayu', 'qayu', 'kaa', 'qaa',
  'кай', 'кей', 'кэй', 'кайи', 'кад', 'гай', 'гей', 'kadastr', 'cadastre',
};

/// Fuzzy wake match — Whisper "Kai"ни turlicha yozadi (qey/kay/gey…): k/q/g + unli(+y/i).
final _wakeRe = RegExp(r'^[kqg][aeiouyаеёиоуэыюяй]{1,2}[yiй]?$');
bool _wakeFuzzy(String w) => w.length >= 2 && w.length <= 4 && _wakeRe.hasMatch(w);

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
  void Function(String route)? navTo; // ovozli sahifa-navigatsiya (oldindan tayyor sahifalar)

  Dio get _dio => ref.read(dioProvider);
  Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));
  void setLang(String lang) => _lang = lang;

  Future<void> startAmbient({
    required String lang,
    required bool Function() onAiPage,
    required bool Function() canListen,
    required void Function() navToAi,
    void Function(String route)? navTo,
  }) async {
    this.onAiPage = onAiPage;
    this.canListen = canListen;
    this.navToAi = navToAi;
    this.navTo = navTo;
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

  // Ambient wake-word tinglash: getAmplitude'ga TAYANMAYDI (Linux'da -160 qaytaradi).
  // Qisqa oyna (≈3.6s) yozib, FAYL energiyasi (RMS) bo'yicha sukut/ovozни ajratadi —
  // sukut bo'lsa STTга yubormaydi, ovoz bo'lsa STT → wake-word ("Kai") tekshiradi.
  static const int _winMs = 3600;
  static const double _rmsMinDbfs = -52.0; // shundan baland = gapirilgan
  Future<String?> _capture() async {
    final path = '${Directory.systemTemp.path}/kadastr_utt.wav';
    try {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    } catch (_) {
      await _sleep(600);
      return null;
    }
    var waited = 0;
    while (_on && !_busy && waited < _winMs) {
      await _sleep(150);
      waited += 150;
    }
    await _stopRec();
    if (!_on || _busy) return null;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 4000) return null; // juda qisqa
      if (_rmsDbfs(bytes) < _rmsMinDbfs) return null; // sukut → STTга yubormaymiz
    } catch (_) {
      return null;
    }
    return path;
  }

  /// WAV (16-bit PCM mono) baytlaridan RMS energiya (dBFS) — platformaga bog'liq emas.
  double _rmsDbfs(List<int> wav) {
    final n = wav.length;
    if (n <= 44) return -160;
    var sum = 0.0;
    var cnt = 0;
    for (var i = 44; i + 1 < n; i += 2) {
      var s = wav[i] | (wav[i + 1] << 8);
      if (s >= 32768) s -= 65536;
      sum += s.toDouble() * s.toDouble();
      cnt++;
    }
    if (cnt == 0) return -160;
    final rms = sqrt(sum / cnt);
    return 20 * (log(rms / 32768.0 + 1e-9) / ln10);
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
      if (_wakeSet.contains(w) || w.startsWith('kadastr') || w.startsWith('cadastre') || _wakeFuzzy(w)) {
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
    // Bosh sahifalarда "Kai" wake-word kerak; AI sahifaсида to'g'ridan-to'g'ri.
    String content = text;
    if (!onAi) {
      final cmd = _stripWake(text);
      if (cmd == null) {
        _busy = false; // wake-word yo'q — e'tibor bermaymiz
        return;
      }
      content = cmd;
    }
    // 1) OVOZLI SAHIFA-NAVIGATSIYA — oldindan tayyor sahifaга o'tadi (jadval shu yerда,
    //    STT aniqligига bog'liq emas). Masalan "noqonuniy yerlar" → /illegal.
    final route = _matchRoute(content);
    if (route != null && navTo != null) {
      navTo!(route);
      await _speak(_navConfirm(route));
      return;
    }
    // 2) Aks holda — AI savol (LLM)
    if (!onAi) {
      navToAi?.call();
      await _sleep(300);
    }
    if (content.trim().length >= 2) {
      await askAI(content);
    } else {
      await _speak(_prompt());
    }
  }

  /// Ovozli buyruq → sahifa yo'li (fuzzy, Whisper imlosiга chidamli). null = AI savol.
  String? _matchRoute(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r"['’ʻ`]"), '');
    bool has(List<String> keys) => keys.any((k) => t.contains(k));
    // noqonuniy egallangan yerlar — aniq so'z + fuzzy undosh-skeleton (nakanuni/egellengen…)
    if (has(['noqonun', 'qonunsiz', 'egallangan', 'egalangan', 'незаконн', 'illegal']) ||
        RegExp(r'g[aeiou]*l+[aeiou]*n[aeiou]*g[aeiou]*n').hasMatch(t) ||
        RegExp(r'n[aeiou]*[qkg][aeiou]*n[aeiou]*n').hasMatch(t)) {
      return '/illegal';
    }
    if (has(['hujjat', 'document', 'документ', 'spravka'])) return '/docs';
    if (has(['telefon', 'phone', 'телефон', 'raqam', 'aloqa'])) return '/phones';
    if (has(['murojaat', 'appeal', 'обращ', 'жалоб', 'shikoyat', 'ariza topshir', 'murojat'])) return '/appeal';
    if (has(['qabul', 'rahbar', 'reception', 'прием', 'приём'])) return '/reception';
    if (has(['yangilik', 'news', 'novost', 'новост'])) return '/news';
    if (has(['ijtimoiy', 'social', 'tarmoq', 'instagram', 'telegram', 'facebook', 'youtube', 'соцсет'])) return '/social';
    if (has(['tuman', 'shahar', 'hudud', 'district', 'район'])) return '/districts';
    if (has(['xizmat', 'service', 'услуг'])) return '/services';
    if (has(['mulk', 'parcel', 'kadastr raqam', 'участок', 'uchastka'])) return '/property';
    if (has(['xatlov', '937'])) return '/xatlov';
    if (has(['bosh sahifa', 'asosiy', 'home', 'главн', 'orqaga'])) return '/';
    return null;
  }

  // Sahifага o'tgaach OVOZLI o'qib beriladigan matn (nafaqat nomi — sahifани tushuntiradi).
  String _navConfirm(String route) {
    const m = {
      '/illegal': {'uz': 'Noqonuniy egallangan yerlar bo‘limi. Bu yerda tuman va shaharlar kesimida noqonuniy yerlar soni ko‘rsatilgan. O‘z ma’lumotingizni tekshirish uchun shaxsингизни tasdiqlang.', 'ru': 'Раздел незаконно занятых земель. Здесь показано количество по районам и городам.', 'en': 'Illegally occupied lands section, by district and city.'},
      '/docs': {'uz': 'Hujjatlar va narxlar bo‘limi. Kadastr xizmatlari uchun kerakli hujjatlar va ularning narxlari.', 'ru': 'Раздел документов и цен на кадастровые услуги.', 'en': 'Documents and prices for cadastre services.'},
      '/phones': {'uz': 'Telefonlar va aloqa raqamlari bo‘limi. Kerakli bo‘lim raqamlarини shu yerdан toping.', 'ru': 'Телефоны и контакты.', 'en': 'Phone numbers and contacts.'},
      '/reception': {'uz': 'Rahbar qabuli bo‘limi. Qabul kunlari bilan tanishing va qabulga yozilишing mumkin.', 'ru': 'Приём руководителя. Можно записаться на приём.', 'en': 'Manager reception. You can book a reception.'},
      '/appeal': {'uz': 'Murojaat yuborish bo‘limi. Ism, telefon va murojaat matnini yozib yuboring — javob telefon orqali beriladi.', 'ru': 'Раздел подачи обращения. Ответ дадут по телефону.', 'en': 'Submit an appeal here. We will reply by phone.'},
      '/social': {'uz': 'Ijtimoiy tarmoqlar bo‘limi. Rasmiy sahifalarга o‘ting.', 'ru': 'Раздел социальных сетей.', 'en': 'Social networks section.'},
      '/news': {'uz': 'Yangiliklar bo‘limi. Palataning so‘nggi yangiliklarи bilan tanishing.', 'ru': 'Раздел новостей.', 'en': 'News section.'},
      '/districts': {'uz': 'Tumanlar va shaharlar bo‘limi. Har bir hudud bo‘yicha ma’lumot va rahbariyat.', 'ru': 'Районы и города, информация по каждому.', 'en': 'Districts and cities information.'},
      '/services': {'uz': 'Xizmatlar bo‘limi. Barcha kadastr xizmatlarини shu yerda ko‘ring.', 'ru': 'Раздел услуг.', 'en': 'Services section.'},
      '/property': {'uz': 'Ko‘chmas mulk tekshiruvi bo‘limi. Kadastr raqami bo‘yicha mulk holatini tekshiring.', 'ru': 'Проверка недвижимости по кадастровому номеру.', 'en': 'Property check by cadastre number.'},
      '/xatlov': {'uz': 'To‘qqiz yuz o‘ttiz yetti-sonli qaror bo‘yicha xatlov bo‘limi. Andijon viloyati tumanları kesimida mahallalar va obyektlar xatlovi. Tuman ustiga bosib batafsil ma’lumotni ko‘ring.', 'ru': 'Раздел описи по постановлению 937 — по районам Андижанской области.', 'en': 'Inventory under Resolution 937, by Andijan districts.'},
      '/': {'uz': 'Bosh sahifa. Kerakli bo‘limni tanlang yoki ovoz bilan ayting.', 'ru': 'Главная страница.', 'en': 'Home page.'},
    };
    return (m[route]?[_lang]) ?? '';
  }

  // ===== TAP-TO-TALK (qo'lda gapirish) — VAD/amplitude'siz, hamma platformada =====
  bool _manual = false;
  String? _manualPath;

  /// Tugmani bosib gapirish: 1-bosish boshlaydi (yozadi), 2-bosish to'xtatib AIга
  /// yuboradi. Linux'da getAmplitude ishlamaydi → VAD o'rniga shu ishlatiladi.
  Future<void> toggleTalk() async {
    if (_manual) {
      await _finishTalk();
      return;
    }
    _busy = true; // ambient loop'ni pauza qiladi (mikrofon to'qnashmasin)
    try { await _player.stop(); } catch (_) {}
    try {
      if (!await _rec.hasPermission()) {
        state = state.copyWith(error: 'mic', recording: false);
        _busy = false;
        return;
      }
      if (await _rec.isRecording()) await _rec.stop();
      final path = '${Directory.systemTemp.path}/kadastr_talk.wav';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
      _manualPath = path;
      _manual = true;
      state = state.copyWith(phase: VoicePhase.listening, heard: '', recording: true, clearError: true);
      Future.delayed(const Duration(seconds: 20), () { if (_manual) _finishTalk(); }); // xavfsizlik cheki
    } catch (_) {
      _manual = false;
      _busy = false;
      state = state.copyWith(error: 'mic', recording: false);
    }
  }

  Future<void> _finishTalk() async {
    if (!_manual) return;
    _manual = false;
    state = state.copyWith(recording: false, phase: VoicePhase.transcribing);
    await _stopRec();
    final path = _manualPath;
    _manualPath = null;
    final text = (path != null) ? await _stt(path) : null;
    if (text != null && text.trim().isNotEmpty) {
      state = state.copyWith(heard: text.trim());
      _logHeard(text.trim());
      // tugma bilan ham: avval sahifa-navigatsiya (oldindan tayyor jadval), so'ng AI
      final route = _matchRoute(text.trim());
      if (route != null && navTo != null) {
        navTo!(route);
        await _speak(_navConfirm(route));
      } else {
        await askAI(text.trim());
      }
    } else {
      final msg = {'uz': 'Eshitmadim, qaytadan urinib ko‘ring.', 'ru': 'Не расслышал, попробуйте снова.', 'en': 'I didn’t catch that, please try again.'}[_lang]!;
      state = state.copyWith(answer: msg);
      await _speak(msg);
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

  /// Telefon ovozli pultдан kelgan buyruq (QR orqali) — wake-word shart emas, to'g'ridan-to'g'ri bajaradi.
  Future<void> handleRemoteText(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    _busy = true; // ambient mikrofonni pauza qiladi (to'qnashmasin)
    try {
      await _player.stop();
    } catch (_) {}
    state = state.copyWith(heard: q, clearError: true);
    _logHeard(q);
    final route = _matchRoute(q);
    if (route != null && navTo != null) {
      navTo!(route);
      await _speak(_navConfirm(route));
      return;
    }
    navToAi?.call();
    await _sleep(250);
    if (q.length >= 2) {
      await askAI(q);
    } else {
      await _speak(_prompt());
    }
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
