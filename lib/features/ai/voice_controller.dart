import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/env.dart';
import '../../core/network/api_client.dart';
import '../../core/network/repository.dart';
import '../../core/services/avatar_player.dart';
import '../../router.dart';
import 'answer_session.dart';
import 'attract_wake_guard.dart';
import 'audio_clip_player.dart';
import 'speech_queue.dart';
import 'wake_word.dart';
import 'wav_tools.dart';

export 'wake_word.dart' show stripWakeWord;

enum VoicePhase { off, listening, transcribing, thinking, speaking }

class VoiceUiState {
  final VoicePhase phase;
  final String heard;
  final String answer;
  final List<List<dynamic>>? table;
  final bool speaking;
  final bool recording; // tap-to-talk: qo'lda yozilyapti
  final bool suggest; // gap chala/tushunarsiz — xizmat turlarini taklif qilamiz
  final String? error;
  const VoiceUiState({
    this.phase = VoicePhase.off,
    this.heard = '',
    this.answer = '',
    this.table,
    this.speaking = false,
    this.recording = false,
    this.suggest = false,
    this.error,
  });

  VoiceUiState copyWith(
          {VoicePhase? phase,
          String? heard,
          String? answer,
          List<List<dynamic>>? table,
          bool? speaking,
          bool? recording,
          bool? suggest,
          String? error,
          bool clearError = false,
          bool clearTable = false}) =>
      VoiceUiState(
        phase: phase ?? this.phase,
        heard: heard ?? this.heard,
        answer: answer ?? this.answer,
        table: clearTable ? null : (table ?? this.table),
        speaking: speaking ?? this.speaking,
        recording: recording ?? this.recording,
        suggest: suggest ?? this.suggest,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Bitta yozib olingan gap (ambient VAD): WAV baytlari + nutq boshi/oxiri vaqti.
class _Utt {
  _Utt(this.wav, this.onsetAt, this.endAt, {this.wakeOnly = false});
  final Uint8List wav;
  final DateTime onsetAt;
  final DateTime endAt;

  /// Zastavka paytida yozilgan — faqat chaqiruv so'zi bilan boshlansa qabul qilinadi.
  final bool wakeOnly;
}

/// Yagona doimiy ovoz dvigateli: mic → VAD → /stt → wake-route → /ai/chat-stream → navbat.
///
/// NAVBAT/EGALIK MODELI (1.9.48): har bir faoliyat (ambient gap, savol, gapirish, qo'lda
/// yozish, pult) `_turn` raqamini oladi. Yangi faoliyat yoki bekor qilish `_turn`ni
/// oshiradi → eski faoliyatning barcha davomlari (chat javobi, TTS, `_busy=false`,
/// `speaking=false`) JIM tashlanadi. Avval eski javob yangisining ovozini o'chirib
/// qo'yardi, sahifa almashgach eski TTS chalinardi va mikrofon TTS paytida yoqilardi.
class VoiceController extends StateNotifier<VoiceUiState> {
  /// [player]/[recorder] — faqat testlar uchun (plaginsiz soxta o'ynatuvchi).
  /// [retryBackoff] — mikrofon ochilmasa qayta urinish oraliqlari (oxirgisi takrorlanadi).
  VoiceController(this.ref,
      {ClipPlayer? player,
      AudioRecorder? recorder,
      this.retryBackoff = const [
        Duration(seconds: 2),
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 30),
      ],
      this.attractPause = const Duration(seconds: Env.attractPauseSec)})
      : _injectedPlayer = player,
        _injectedRec = recorder,
        super(const VoiceUiState());
  final Ref ref;
  final List<Duration> retryBackoff;

  /// Zastavkada chaqiruvsiz ko'p bo'lak ketsa — tinglash pauzasi (duty-cycle cheki).
  final Duration attractPause;
  final ClipPlayer? _injectedPlayer;
  final AudioRecorder? _injectedRec;
  AudioRecorder? _recInst;
  AudioRecorder get _rec => _recInst ??= _injectedRec ?? AudioRecorder();
  ClipPlayer? _clipsInst;
  ClipPlayer get _clips => _clipsInst ??= _injectedPlayer ??
      AudioClipPlayer(onTrace: (c, ev) {
        // haqiqiy birinchi TOVUSH vaqti (resume) — latency logi uchun
        if (ev == 'resumed' && c.id >= -1) _firstSoundAt ??= DateTime.now();
      });
  DateTime? _firstSoundAt;

  /// Test/diagnostika: ambient loop mikrofonni hozir kutyaptimi (false) yoki band (true).
  bool get busy => _busy;

  /// Ambient tinglash ishga tushganmi.
  bool get isOn => _on;

  /// Zastavka-uyg'otish qo'riqchisi (o'z videosidan qayta-qayta uyg'onmaslik).
  late final AttractWakeGuard attractGuard = AttractWakeGuard(log: _log);

  /// Zastavka ochiq — faqat "Alomat" bilan BOSHLANGAN gap qabul qilinadi.
  bool Function()? wakeOnlyMode;

  /// Zastavkani yopish (teginish bilan bir xil) — zastavkada uyg'onilganda.
  void Function()? dismissAttract;

  /// Ekranga teginish: zastavka-qo'riqchisi qayta yoqiladi, duty-cycle pauzasi bekor.
  void noteTouch() {
    attractGuard.onTouch();
    _attractClips.clear();
    _attractPausedUntil = null;
  }

  // Zastavka duty-cycle: chaqiruvsiz yuborilgan bo'laklar vaqti (oxirgi 60s).
  final _attractClips = <DateTime>[];
  DateTime? _attractPausedUntil;

  /// Zastavka tinglash duty-cycle pauzasida (diagnostika/test).
  bool get attractPaused {
    final u = _attractPausedUntil;
    return u != null && DateTime.now().isBefore(u);
  }

  /// Chaqiruvsiz zastavka bo'lagi yuborildi — 60s ichida ≥6 bo'lsa 60s pauza.
  void _noteAttractClipWithoutWake() {
    final now = DateTime.now();
    _attractClips.add(now);
    _attractClips.removeWhere((t) => now.difference(t).inSeconds >= Env.attractClipWindowSec);
    if (_attractClips.length >= Env.attractClipCap) {
      _attractClips.clear();
      _attractPausedUntil = now.add(attractPause);
      _log('screensaver: ${Env.attractClipCap} clips in ${Env.attractClipWindowSec}s without a wake '
          '— screensaver listening paused for ${attractPause.inSeconds}s');
    }
  }

  bool _on = false;
  bool _busy = false;
  String _lang = 'uz';
  DateTime _lastRepeat = DateTime.fromMillisecondsSinceEpoch(0);
  // Yolg'iz "Alomat"dan keyingi 15s "suhbat oynasi" — AI sahifasida ismsiz davom-savol.
  DateTime _followUntil = DateTime.fromMillisecondsSinceEpoch(0);
  // Aks-sado oynasi: shu vaqtgacha NUTQ BOSHI sanalmaydi (mikrofon baribir yozadi).
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  // EXO-FILTR (1.9.36): AI o'z aytgan gapining BO'LAGINI qayta eshitsa — savol EMAS.
  // Oqimli javobda TO'LIQ aytilgan matn (filler + hamma jumlalar) shu yerga yoziladi.
  String _lastSpokenNorm = '';
  DateTime? _spokeEndAt;

  // ---- faoliyat egaligi ----
  int _turn = 0;
  AnswerSession? _session;
  SpeechQueue? _speechQ;
  CancelToken? _turnCancel;
  bool _qActive = false; // savol-javob jarayonda (AI sahifa intro/greet'ni o'tkazib yuboradi)
  DateTime? _voiceEntryAt; // ovoz bilan AI sahifaga o'tildi (intro/greet kerak emas)
  bool _streamUnsupported = false; // server /ai/chat-stream bilmaydi (404) — sessiya davomida
  DateTime _lastNet = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastEngaged = DateTime.fromMillisecondsSinceEpoch(0);
  // latency (joriy ovozli savol)
  DateTime? _turnEos;
  int _turnSttMs = -1;

  bool Function()? onAiPage; // direct mode (no wake needed)
  bool Function()? canListen; // false on the appeal page (camera owns the mic)
  void Function()? navToAi;
  void Function(String route)? navTo; // ovozli sahifa-navigatsiya (oldindan tayyor sahifalar)

  Dio get _dio => ref.read(dioProvider);
  Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

  // ignore: avoid_print
  void _log(String m) => print('[voice] $m');
  // ignore: avoid_print
  void _lat(String m) => print('[voice-latency] $m');

  /// Savol-javob jarayonda (so'rov yuborilgan yoki javob gapirilmoqda).
  bool get inQuestion => _qActive;

  /// Foydalanuvchi bilan hozir muloqot bormi (avto-yangilanish shu payt o'rnatmaydi).
  bool get engaged =>
      _busy || _manual || _qActive || state.speaking || state.recording ||
      DateTime.now().difference(_lastEngaged).inSeconds < 90;

  /// AI sahifasiga OVOZ bilan o'tildi (bir martalik) — sahifa intro-video/salomni
  /// o'ynatmaydi, eski javobni tozalamaydi (yangi savol javobi kelyapti).
  bool consumeVoiceEntry() {
    final at = _voiceEntryAt;
    _voiceEntryAt = null;
    return at != null && DateTime.now().difference(at).inSeconds < 5;
  }

  void setLang(String lang) {
    if (lang == _lang) return;
    _lang = lang;
    // Til almashdi — eski tildagi javob davom etmasin (aralash tilli ovoz bo'lmasin).
    if (state.speaking || _qActive) unawaited(stopSpeaking());
    if (_on) unawaited(_primePhrases());
  }

  // ===================== OLDINDAN KESHLANGAN IBORALAR =====================
  // Faqat QAT'IY iboralar (wake javobi + filler) keshlanadi — foydalanuvchi savoli EMAS.
  final _phraseAudio = <String, Uint8List>{};
  final _phraseLoading = <String, Future<Uint8List?>>{};
  bool _warmedPlayer = false;
  int _fillerIdx = 0;

  static String _wakeText(String lang) => const {
        'uz': 'Labbay! Eshitaman.',
        'ru': 'Да, слушаю!',
        'en': 'Yes, I am listening!',
      }[lang] ??
      'Labbay! Eshitaman.';

  static const _fillers = {
    'uz': ['Hozir aytaman.', 'Bir soniya.'],
    'ru': ['Секунду.', 'Сейчас скажу.'],
    'en': ['One moment.', 'Let me check.'],
  };

  Future<Uint8List?> _loadPhrase(String lang, String voice, String text) {
    final key = '$lang|$voice|$text';
    final cached = _phraseAudio[key];
    if (cached != null) return Future.value(cached);
    final pending = _phraseLoading[key];
    if (pending != null) return pending;
    final job = () async {
      try {
        final r = await _dio.get<List<int>>('/tts/synthesize',
            queryParameters: {'text': text, 'voice': voice, 'lang': lang},
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 25)));
        final d = r.data;
        if (d == null || d.length < 200) return null;
        final bytes = d is Uint8List ? d : Uint8List.fromList(d);
        _phraseAudio[key] = bytes;
        return bytes;
      } catch (_) {
        return null;
      }
    }();
    _phraseLoading[key] = job;
    job.whenComplete(() => _phraseLoading.remove(key));
    return job;
  }

  String? _knownVoice() {
    final av = ref.read(avatarProvider).valueOrNull;
    return av == null ? null : (av.male ? 'sardor' : 'madina');
  }

  Future<String> _voiceWait(int ms) async {
    final v = _knownVoice();
    if (v != null) return v;
    try {
      final av = await ref.read(avatarProvider.future).timeout(Duration(milliseconds: ms));
      return av.male ? 'sardor' : 'madina';
    } catch (_) {
      return 'madina';
    }
  }

  bool _primeNeeded = false;

  /// Tayyor iboralar yuklanmagan bo'lsa (startda tarmoq yo'q edi) — keyingi muvaffaqiyatli
  /// tarmoq so'rovidan keyin qayta urinadi.
  void _maybeRetryPrime() {
    if (_primeNeeded && _on) {
      _primeNeeded = false;
      _log('retrying phrase prefetch after network recovered');
      unawaited(_primePhrases());
    }
  }

  /// Test/diagnostika: wake + filler iboralari keshlanganmi (joriy til/ovoz).
  @visibleForTesting
  bool get phrasesReady {
    final v = _knownVoice() ?? 'madina';
    final list = [_wakeText(_lang), if (Env.fillerEnabled) ...(_fillers[_lang] ?? _fillers['uz']!)];
    return list.every((t) => _phraseAudio['$_lang|$v|$t'] != null);
  }

  Future<void> _primePhrases() async {
    final lang = _lang;
    final voice = await _voiceWait(2000);
    if (!_on) return;
    final wake = await _loadPhrase(lang, voice, _wakeText(lang));
    if (wake == null) _primeNeeded = true;
    final clips = _clips;
    if (wake != null && !_warmedPlayer && clips is AudioClipPlayer) {
      _warmedPlayer = true;
      unawaited(clips.warmUp(wake)); // MP3 dekoderi birinchi javobdan oldin "isiydi"
    }
    if (Env.fillerEnabled) {
      for (final f in _fillers[lang] ?? _fillers['uz']!) {
        unawaited(_loadPhrase(lang, voice, f).then((b) {
          if (b == null) _primeNeeded = true;
        }));
      }
    }
  }

  (String, Uint8List)? _pickFiller(String lang, String voice) {
    final list = _fillers[lang] ?? _fillers['uz']!;
    for (var k = 0; k < list.length; k++) {
      final i = (_fillerIdx + k) % list.length;
      final b = _phraseAudio['$lang|$voice|${list[i]}'];
      if (b != null) {
        _fillerIdx = i + 1; // navbatma-navbat almashadi
        return (list[i], b);
      }
    }
    return null;
  }

  // ===================== HAYOT SIKLI =====================

  Future<void> startAmbient({
    required String lang,
    required bool Function() onAiPage,
    required bool Function() canListen,
    required void Function() navToAi,
    void Function(String route)? navTo,
    bool Function()? wakeOnly,
    void Function()? dismissAttract,
  }) async {
    this.onAiPage = onAiPage;
    this.canListen = canListen;
    this.navToAi = navToAi;
    this.navTo = navTo;
    if (wakeOnly != null) wakeOnlyMode = wakeOnly;
    if (dismissAttract != null) this.dismissAttract = dismissAttract;
    _lang = lang;
    await _tryStart();
  }

  // Ishga tushish urinishlari (ilova ochilishida qurilma hali tayyor bo'lmasligi mumkin).
  int _startFails = 0;
  bool _starting = false;
  Timer? _startRetry;
  int _recFails = 0; // ketma-ket _rec.start xatolari (qayta ochish backoff)

  Duration _backoff(int fails) => retryBackoff[(fails - 1).clamp(0, retryBackoff.length - 1)];

  /// Mikrofon ruxsati/qurilma tayyor bo'lsa ambient'ni boshlaydi; bo'lmasa 2s, 5s, 10s,
  /// keyin har 30s qayta urinadi (log faqat birinchi xato va tiklanishda).
  Future<void> _tryStart() async {
    if (_on || _starting || _disposed) return;
    _starting = true;
    _startRetry?.cancel();
    _startRetry = null;
    var ok = false;
    try {
      ok = await _rec.hasPermission();
    } catch (_) {
      ok = false;
    }
    _starting = false;
    if (_disposed || _on) return;
    if (!ok) {
      _startFails++;
      if (_startFails == 1) _log('mic not ready — retrying (${retryBackoff.map((d) => d.inSeconds).join('s, ')}s…)');
      if (state.error != 'mic') state = state.copyWith(error: 'mic');
      _startRetry = Timer(_backoff(_startFails), _tryStart);
      return;
    }
    if (_startFails > 0) _log('mic ready after $_startFails failed attempt(s)');
    _startFails = 0;
    _on = true;
    unawaited(AudioClipPlayer.sweepStaleTempFiles());
    unawaited(_primePhrases());
    _warmConnection(force: true);
    state = state.copyWith(phase: VoicePhase.listening, clearError: true);
    unawaited(_loop());
  }

  bool _wakeOnlyNow() => wakeOnlyMode?.call() ?? false;

  /// Hozir tinglash mumkinmi: /appeal, /face-enroll, intro — yo'q; zastavkada faqat
  /// qo'riqchi o'chirmagan bo'lsa (wake-only).
  bool _listenAllowed() {
    if (canListen != null && !canListen!()) return false;
    if (_wakeOnlyNow() && (attractGuard.blocked || attractPaused)) return false;
    return true;
  }

  /// Joriy faoliyatni DARHOL bekor qiladi: HTTP oqimi yopiladi, navbatdagi audio
  /// to'xtaydi, avatar-video to'xtaydi. `_turn` oshadi → eski davomlar jim tashlanadi.
  Future<void> _cancelTurn() {
    _turn++;
    _qActive = false;
    final active = _session != null || _speechQ != null || state.speaking;
    final s = _session;
    final q = _speechQ;
    _session = null;
    _speechQ = null;
    final ct = _turnCancel;
    _turnCancel = null;
    if (ct != null && !ct.isCancelled) ct.cancel('turn');
    if (!active) return Future.value();
    final futs = <Future<void>>[
      if (s != null) s.cancel(),
      if (q != null) q.cancel(),
      _clips.stop(),
      ref.read(avatarPlayerProvider.notifier).stop(),
    ];
    return Future.wait(futs).then((_) {}, onError: (Object _) {});
  }

  /// Yangi faoliyatni boshlaydi (oldingisini bekor qilib) — egalik raqamini qaytaradi.
  int _takeOver() {
    _busy = true;
    unawaited(_cancelTurn());
    // eski ovoz to'xtatildi — "gapiryapti" holati ham tozalanadi (avval tap-to-talk
    // yozuvida ham avatar "gapiryapti" nurida qolardi)
    if (state.speaking) state = state.copyWith(speaking: false);
    return _turn;
  }

  /// [t] hali ham joriy bo'lsa — mikrofonni ambient'ga qaytaradi.
  void _release(int t, {bool spoke = true, int? quietMs}) {
    if (t != _turn) return; // boshqa faoliyat egallagan — tegmaymiz
    _qActive = false;
    _turnCancel = null;
    if (spoke) {
      _spokeEndAt = DateTime.now();
      _lastEngaged = _spokeEndAt!;
      _quietUntil = DateTime.now().add(Duration(milliseconds: quietMs ?? Env.echoQuietMs));
    }
    if (state.speaking || state.phase == VoicePhase.thinking || state.phase == VoicePhase.transcribing ||
        state.phase == VoicePhase.speaking) {
      state = state.copyWith(speaking: false, phase: _on ? VoicePhase.listening : VoicePhase.off);
    }
    if (!_manual && !_manualStarting) _busy = false;
  }

  /// Gapirishni (TTS + avatar video + kutilayotgan AI javobi) DARHOL to'xtatadi — sahifa
  /// almashsa yoki zastavka chiqsa fonda ovoz qolmasin. Ambient tinglash o'chmaydi.
  Future<void> stopSpeaking() async {
    final wasSpeaking = state.speaking;
    final f = _cancelTurn();
    if (!_manual && !_manualStarting) _busy = false;
    if (wasSpeaking) {
      // faqat haqiqatan gapirayotgan bo'lsa aks-sado oynasi (bo'sh navigatsiyada
      // "Alomat" boshi kesilmasin)
      _spokeEndAt = DateTime.now();
      _quietUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    if (state.speaking || state.phase == VoicePhase.thinking || state.phase == VoicePhase.speaking) {
      state = state.copyWith(speaking: false, phase: _on ? VoicePhase.listening : VoicePhase.off);
    }
    await f;
  }

  Future<void> stop() async {
    _on = false;
    await _cancelTurn();
    _busy = false;
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    try {
      await _clips.stop();
    } catch (_) {}
    state = state.copyWith(phase: VoicePhase.off, speaking: false);
  }

  /// AI sahifasiga qayta kirilganda ESKI javob/jadval tozalanadi.
  void resetConversation() {
    state = state.copyWith(answer: '', heard: '', clearTable: true, suggest: false);
  }

  /// Salomlashuv (AI sahifaga kirganda).
  Future<void> greet(String text) async {
    if (_busy) return;
    final t = _takeOver();
    await _speak(text, turn: t, video: true); // salomlashuv — tayyor video bo'lsa lab-sinx
  }

  /// Foydalanuvchi QO'LDA (tugma bilan) sahifa ochganda — sahifani OVOZda tanishtiradi.
  Future<void> announcePage(String route) async {
    if (_busy) return; // allaqachon gapiryapti — bezovta qilmaymiz
    final intro = _pageIntro(route);
    if (intro == null || intro.isEmpty) return;
    final t = _takeOver();
    await _speak(intro, turn: t);
  }

  String? _pageIntro(String route) {
    final r = route.split('?').first;
    if (r.startsWith('/district/')) {
      final nm = Uri.decodeComponent(r.substring('/district/'.length));
      return _lang == 'ru'
          ? '$nm — информация по району.'
          : _lang == 'en'
              ? '$nm district information.'
              : '$nm bo‘yicha ma’lumot.';
    }
    const uz = {
      '/services': 'Kadastr xizmatlari bo‘limi. Kerakli xizmatni tanlang yoki menga ayting.',
      '/districts': 'Tumanlar bo‘limi. Har bir tuman bo‘yicha ma’lumotni ko‘rishingiz mumkin.',
      '/phones': 'Aloqa raqamlari bo‘limi. Kerakli telefon raqamini shu yerdan toping.',
      '/docs': 'Hujjatlar bo‘limi. Kerakli hujjat va ma’lumotlar shu yerda.',
      '/xatlov': 'Xatlov bo‘limi — to‘qqiz yuz o‘ttiz yetti ishchi guruh ma’lumotlari.',
      '/property': 'Ko‘chmas mulk bo‘limi.',
      '/illegal': 'Noqonuniy egallangan yerlar bo‘limi.',
      '/appeal': 'Murojaat bo‘limi. Fikr yoki shikoyatingizni yozing yoki menga ayting.',
      '/reception': 'Rahbariyat qabuli bo‘limi.',
      '/news': 'Yangiliklar bo‘limi.',
      '/social': 'Ijtimoiy tarmoqlar bo‘limi.',
    };
    const ru = {
      '/services': 'Раздел кадастровых услуг. Выберите нужную услугу или скажите мне.',
      '/districts': 'Раздел районов. Можно посмотреть данные по каждому району.',
      '/phones': 'Раздел телефонов. Найдите нужный номер здесь.',
      '/docs': 'Раздел документов. Нужные документы и сведения здесь.',
      '/xatlov': 'Раздел хатлова — данные рабочей группы девятьсот тридцать семь.',
      '/property': 'Раздел недвижимости.',
      '/illegal': 'Раздел незаконно занятых земель.',
      '/appeal': 'Раздел обращений. Напишите или скажите ваше обращение.',
      '/reception': 'Раздел приёма руководством.',
      '/news': 'Раздел новостей.',
      '/social': 'Раздел социальных сетей.',
    };
    const en = {
      '/services': 'Cadastre services section. Choose a service or tell me.',
      '/districts': 'Districts section. You can view data for each district.',
      '/phones': 'Phone numbers section. Find the number you need here.',
      '/docs': 'Documents section. Needed documents and information are here.',
      '/xatlov': 'Survey section — working group nine thirty seven data.',
      '/property': 'Real estate section.',
      '/illegal': 'Illegally occupied lands section.',
      '/appeal': 'Appeals section. Write or tell me your appeal.',
      '/reception': 'Management reception section.',
      '/news': 'News section.',
      '/social': 'Social networks section.',
    };
    final m = _lang == 'ru' ? ru : _lang == 'en' ? en : uz;
    return m[r];
  }

  // ===================== AMBIENT TINGLASH =====================

  Future<void> _loop() async {
    while (_on) {
      int? lt; // shu iteratsiya olgan egalik (xato bo'lsa bo'shatiladi)
      try {
        if (_busy) {
          await _sleep(80);
          continue;
        }
        if (!_listenAllowed()) {
          await _sleep(300); // appeal/face-enroll/intro yoki zastavka-qo'riqchisi — tinglamaymiz
          continue;
        }
        if (state.phase != VoicePhase.listening) state = state.copyWith(phase: VoicePhase.listening);
        final utt = await _capture();
        if (!_on) break;
        if (utt == null || _busy || _manual || _manualStarting) continue;
        final t = lt = _takeOver();
        state = state.copyWith(phase: VoicePhase.transcribing);
        final sentAt = DateTime.now();
        // Zastavkada faqat birinchi 2.5s (ism baribir birinchi so'z) + `mode=wake`:
        // server Gemini-fallback, dataset va chuchkirish tasnifini o'tkazib yuboradi.
        final clip = utt.wakeOnly ? truncateWav(utt.wav, Env.wakeClipMs) : utt.wav;
        var text = await _stt(clip, wakeMode: utt.wakeOnly);
        if (t != _turn) continue; // tugma/pult/sahifa egalladi — natija eskirdi
        _turnEos = utt.endAt;
        _turnSttMs = DateTime.now().difference(sentAt).inMilliseconds;
        _lat('vad_end→stt_sent_ms=${sentAt.difference(utt.endAt).inMilliseconds} stt_ms=$_turnSttMs '
            'utt_ms=${utt.endAt.difference(utt.onsetAt).inMilliseconds} bytes=${utt.wav.length}');
        if (utt.wakeOnly) {
          // ZASTAVKA: faqat "Alomat" bilan BOSHLANGAN gap (davom-oynasi/buyruq/chuchkirish yo'q).
          final cmd = text == null || !_valid(text) ? null : stripWakeWord(text, within: 1);
          if (cmd == null) {
            _noteAttractClipWithoutWake();
            _release(t, spoke: false); // video/begona nutq — jim (serverga log ham yo'q)
            continue;
          }
          _attractClips.clear();
          if (!attractGuard.onWake()) {
            _release(t, spoke: false);
            continue;
          }
          _log('screensaver wake');
          if (!identical(clip, utt.wav)) {
            // Gap 2.5s dan uzun edi — ismdan keyingi savol kesilgan bo'lishi mumkin: faqat
            // CHAQIRUV tasdiqlangach to'liq gapni bir marta oddiy rejimda qayta tanitamiz.
            final full = await _stt(utt.wav);
            if (t != _turn) continue;
            if (full != null && _valid(full) && stripWakeWord(full, within: 1) != null) text = full;
          }
          dismissAttract?.call(); // teginish bilan bir xil: zastavka yopiladi
          final answered = await _handle(text!, t, fromAttract: true);
          // Uyg'onish gapidagi savolga MAZMUNLI javob berildi — haqiqiy odam (video emas).
          if (answered) attractGuard.onRealSpeech();
          continue;
        }
        if (_lastSttEvent == 'sneeze') {
          // CHUCHKIRISH aniqlandi (server YAMNet) — odob bilan "Sog' bo'ling!"
          await _speak(_blessYou(), turn: t);
          continue;
        }
        if (text != null && text.isNotEmpty && _isEcho(text, utt.onsetAt)) {
          // AI o'z ovozining bo'lagini eshitdi — savol EMAS
          _logHeard(text, acted: false);
          _release(t, spoke: false);
          continue;
        }
        if (text != null && text.isNotEmpty && _valid(text)) {
          await _handle(text, t);
        } else if ((onAiPage?.call() ?? false) &&
            text != null &&
            stripWakeWord(text) != null &&
            DateTime.now().difference(_lastRepeat).inSeconds >= 20) {
          // AI sahifasida gap CHALA/TUSHUNARSIZ — "tushunmadim" + XIZMAT TURLARINI taklif.
          _lastRepeat = DateTime.now();
          state = state.copyWith(suggest: true, answer: '', clearTable: true);
          await _speak(_suggestPrompt(), turn: t);
        } else {
          _release(t, spoke: false);
        }
      } catch (e) {
        // Loop HECH QACHON o'lmasin (avval istisno bo'lsa mikrofon abadiy o'chib qolardi).
        _log('loop error: $e');
        if (lt != null) _release(lt, spoke: false);
        await _sleep(500);
      }
    }
  }

  // Ambient tinglash — DINAMIK OYNA (gap tugashini kutadi).
  // Windows: getAmplitude bilan onset→sukut endpointing (to'liq gapni yozadi).
  // Linux: getAmplitude o'lik (-160) → ESKI qat'iy oynaga qaytadi.
  static const int _winMs = 5000; // Linux fallback qat'iy oyna
  static const int _pollMs = 120; // amplituda tekshiruv qadami
  // Gap boshlanishini kutish. Avval 4200 edi → har 4.2s yozuvchi qayta ishga tushirilib
  // ~0.1-0.3s "kar" bo'shliq qolardi (so'z boshi yo'qolardi). Boshidagi sukut endi
  // kesib tashlanadi, shuning uchun uzun oyna yuklashni sekinlashtirmaydi.
  static const int _preOnsetMaxMs = 8000;
  static const int _preRollMs = 500; // nutq boshidan oldin saqlanadigan qism
  static const int _maxUttMs = 11000; // eng uzun gap
  static const int _maxWakeUttMs = 6000; // zastavkada: "Alomat" + qisqa savol
  static const double _rmsMinDbfs = -48.0; // muvozanat: user ovozi yutilmasin, uzoq shovqin ham kirmasin

  Future<_Utt?> _capture() async {
    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}kadastr_utt.wav';
    var wakeOnly = _wakeOnlyNow();
    try {
      await _rec.start(
          const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 16000,
              numChannels: 1,
              autoGain: true,
              noiseSuppress: true,
              echoCancel: true),
          path: path);
      if (_recFails > 0) _log('recorder opened again after $_recFails failure(s)');
      _recFails = 0;
    } catch (e) {
      // Qurilma tayyor emas (ilova ochilishi, USB mikrofon...) — backoff bilan qayta,
      // har 600 ms da urinib logni to'ldirmaymiz.
      _recFails++;
      if (_recFails == 1) _log('recorder open failed: $e — retrying with backoff');
      await Future<void>.delayed(_backoff(_recFails));
      return null;
    }
    final sw = Stopwatch()..start();
    final startedAt = DateTime.now();
    var spoken = 0, silence = 0;
    var ampAlive = false, onset = false;
    var onsetMs = 0;
    var hitMax = false;
    DateTime? onsetAt;
    while (_on && !_busy) {
      await _sleep(_pollMs);
      if (_manual || _manualStarting) return null; // tap-to-talk → mikrofon unga tegishli
      if (!_listenAllowed()) break; // /appeal, face-enroll, intro, qo'riqchi → mikrofonni bo'shatamiz
      if (!wakeOnly && _wakeOnlyNow()) wakeOnly = true; // zastavka yozuv o'rtasida ochildi
      double db = -160;
      try {
        db = (await _rec.getAmplitude()).current;
      } catch (_) {}
      if (db > -120) ampAlive = true; // Linux -160 qaytaradi → o'lik deb bilamiz
      final el = sw.elapsedMilliseconds;
      if (!ampAlive) {
        if (el >= _winMs) break; // Amplituda yo'q (Linux) → eski qat'iy oyna
        continue;
      }
      if (!onset) {
        // Aks-sado oynasida (AI endigina gapirdi) nutq boshi SANALMAYDI — lekin yozuv
        // davom etadi, shuning uchun oyna tugashi bilan foydalanuvchi gapi yo'qolmaydi.
        final quiet = DateTime.now().isBefore(_quietUntil);
        if (!quiet && db > Env.onsetDb) {
          onset = true;
          onsetMs = el - _pollMs < 0 ? 0 : el - _pollMs;
          onsetAt = DateTime.now();
          spoken = 0;
          silence = 0;
          _warmConnection(); // gapirayotganda TLS ulanish tayyorlanadi → /stt darhol ketadi
        } else if (el >= _preOnsetMaxMs) {
          break; // gap yo'q → sukut
        }
      } else {
        spoken += _pollMs;
        if (db < Env.stopDb) {
          silence += _pollMs;
          if (silence >= Env.endSilenceMs) break; // gap tugadi
        } else {
          silence = 0;
        }
        // Zastavkada gap qisqa bo'ladi ("Alomat, ..."); uzluksiz video ovozi cheklovga
        // yetadi — u STT'ga yuborilmaydi (server yuklamasi).
        if (spoken >= (wakeOnly ? _maxWakeUttMs : _maxUttMs)) {
          hitMax = true;
          break;
        }
      }
    }
    if (_manual || _manualStarting) return null;
    await _stopRec();
    final endAt = DateTime.now();
    if (!_on || _busy) return null;
    if (!_listenAllowed()) return null;
    if (_wakeOnlyNow()) wakeOnly = true;
    // Zastavka: nutq boshi bo'lmasa — yuborilmaydi. 6s cheklovga yetgan (uzluksiz) gap ham
    // yuboriladi — lekin faqat birinchi 2.5s (`mode=wake`); yuklamani duty-cycle cheklaydi.
    if (wakeOnly && !onset) return null;
    if (hitMax) _log('utterance hit the ${wakeOnly ? _maxWakeUttMs : _maxUttMs} ms cap');
    try {
      final raw = await File(path).readAsBytes();
      if (raw.length < 4000) return null; // juda qisqa
      // Nutqdan OLDINGI sukutni kesamiz (preRoll qoladi): yuklash kichik, STT tez, va
      // RMS-darvoza sukut bilan "suyultirilmaydi" (avval pauzadan keyin past ovozda
      // aytilgan qisqa "Alomat" butun 4s fayl bo'yicha o'rtachalanib RAD etilardi).
      final wav = onset ? trimWavStart(raw, onsetMs - _preRollMs) : raw;
      // SUKUT/SHOVQIN-DARVOZA: RMS + CREST (peak−rms). Nutq dinamik (crest >~9dB).
      final lv = wavLevels(wav);
      if (lv.$1 < _rmsMinDbfs) return null;
      if (lv.$2 - lv.$1 < 7.0 && lv.$1 < -30) return null;
      return _Utt(wav, onsetAt ?? startedAt, endAt, wakeOnly: wakeOnly);
    } catch (_) {
      return null;
    }
  }

  Future<void> _stopRec() async {
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
  }

  /// Gapirish boshlanishi bilan (yoki startda) API ulanishini isitadi: /stt yuklash
  /// yangi TCP+TLS qo'l siqishini kutmaydi. 20s ichida tarmoq bo'lgan bo'lsa — kerak emas.
  void _warmConnection({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNet).inSeconds < 20) return;
    _lastNet = now;
    _dio
        .get('/health', options: Options(receiveTimeout: const Duration(seconds: 5)))
        .then((_) {}, onError: (Object _) {});
  }

  /// Oxirgi /stt javobidagi hodisa (masalan 'sneeze' — chuchkirish).
  String _lastSttEvent = '';

  Future<String?> _stt(Uint8List bytes, {bool wakeMode = false}) async {
    _lastSttEvent = '';
    final timer = Stopwatch()..start();
    try {
      if (bytes.length < 1500) return null;
      for (var attempt = 0;; attempt++) {
        try {
          final r = await _dio.post(
            '/stt',
            queryParameters: {'lang': _lang, if (wakeMode) 'mode': 'wake'},
            data: Stream.fromIterable([bytes]), // BUTUN bayt bir bo'lakda
            options: Options(contentType: 'application/octet-stream', headers: {Headers.contentLengthHeader: bytes.length}),
          );
          _lastNet = DateTime.now();
          _maybeRetryPrime();
          final m = Map<String, dynamic>.from(r.data as Map);
          if (m['error'] != null) return null;
          _lastSttEvent = (m['event'] ?? '').toString();
          return (m['text'] ?? '').toString().trim();
        } on DioException catch (e) {
          // Server yopib qo'ygan keep-alive ulanish — bir marta darhol qayta urinamiz.
          final stale = e.type == DioExceptionType.connectionError ||
              (e.type == DioExceptionType.unknown && (e.error is HttpException || e.error is SocketException));
          if (attempt == 0 && stale && timer.elapsedMilliseconds < 3000) continue;
          return null;
        }
      }
    } catch (_) {
      return null;
    } finally {
      _lat('stt_ms=${timer.elapsedMilliseconds}');
    }
  }

  /// Chuchkirishga javob — "Sog' bo'ling!" (server YAMNet bilan aniqlaydi, event:'sneeze').
  String _blessYou() => {
        'uz': 'Sog‘ bo‘ling!',
        'ru': 'Будьте здоровы!',
        'en': 'Bless you!',
      }[_lang]!;

  bool _valid(String text) {
    final s = text.replaceAll(RegExp(r'[.,!?\s\d]'), '');
    if (s.length < 2) return false;
    final latin = RegExp(r'[A-Za-zÀ-ɏʻ‘’]').allMatches(text).length;
    final cyr = RegExp(r'[Ѐ-ӿ]').allMatches(text).length;
    final foreign = RegExp(r'[؀-ۿऀ-ॿঀ-৿฀-๿぀-ヿ一-鿿가-힯]').allMatches(text).length;
    if (_lang == 'ru') return cyr >= 2 && foreign <= cyr;
    // uz/en: STT lotin yozadi; kirill USTUN kelsa — buzuq eshitish (ruscha javob chiqmasin)
    return latin >= 2 && foreign <= latin && cyr <= latin;
  }

  String _normTxt(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"['’ʻʼ`.,!?:;()\-—]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Eshitilgan matn AI'ning oxirgi aytgan gapining bo'lagi (aks-sado)mi?
  /// Aks-sado FAQAT AI gapirib bo'lgach [Env.echoWindowMs] ichida boshlangan nutqda
  /// bo'lishi mumkin (mikrofon gapirish paytida o'chiq). Keyinroq berilgan davom-savol
  /// javob so'zlarini takrorlasa ham (masalan "Andijon tumanida auksion...") rad ETILMAYDI.
  bool _isEcho(String text, DateTime onsetAt) {
    final end = _spokeEndAt;
    if (_lastSpokenNorm.isEmpty || end == null) return false;
    if (onsetAt.difference(end).inMilliseconds > Env.echoWindowMs) return false;
    // ISM bilan boshlangan gap: AI o'zi ismni aytmagan bo'lsa — bu aks-sado bo'lishi
    // MUMKIN EMAS (avval "Alomat, Andijon tumanida auksion qachon?" javobdagi so'zlar
    // bilan 60% mos kelib, haqiqiy davom-savol tashlab yuborilardi). Aytgan bo'lsa —
    // faqat ismdan keyingi qism tekshiriladi.
    final afterWake = stripWakeWord(text, within: 1);
    if (afterWake != null) {
      final spokeName = _lastSpokenNorm.split(' ').any(isWakeToken);
      if (!spokeName) return false;
      if (afterWake.isNotEmpty) text = afterWake;
    }
    final a = _normTxt(text);
    if (a.length < 8) {
      // Qisqa bo'lak (masalan "Alomat" — javobda ism tilga olingan) — butun so'z sifatida
      // aytilgan gap ichida bo'lsa aks-sado (o'zini o'zi uyg'otmasin).
      return a.length >= 4 && ' $_lastSpokenNorm '.contains(' $a ');
    }
    if (_lastSpokenNorm.contains(a)) return true; // bo'lak aynan aytilgan gap ichida
    final aw = a.split(' ').where((w) => w.length > 2).toList();
    if (aw.length < 3) return false;
    final bw = _lastSpokenNorm.split(' ').toSet();
    final hit = aw.where(bw.contains).length;
    return hit / aw.length >= 0.6; // so'zlarning 60%+ mos — aks-sado
  }

  /// Test: [text] hozir (AI gapirib bo'lgач) eshitilsa aks-sado deb tashlanadimi.
  @visibleForTesting
  bool debugIsEcho(String text) => _isEcho(text, DateTime.now());

  /// true = savolga mazmunli javob berildi (zastavka qo'riqchisi uchun).
  Future<bool> _handle(String text, int t, {bool fromAttract = false}) async {
    state = state.copyWith(heard: text, suggest: false);
    final onAi = onAiPage?.call() ?? false;
    // HAMMA sahifada faqat ISM ("Alomat") bilan qabul qilinadi. Istisno: yolg'iz ism
    // aytilgandan keyingi 15s "suhbat oynasi" — davom savoli ISMSIZ ham qabul qilinadi.
    // Mikrofon TUGMASI esa ism talab qilmaydi.
    final cmd = stripWakeWord(text);
    String content;
    if (cmd != null) {
      content = cmd;
    } else if (onAi && DateTime.now().isBefore(_followUntil)) {
      content = text;
      _followUntil = DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      _logHeard(text, acted: false); // eshitildi, lekin ism yo'q — E'TIBORSIZ
      _release(t, spoke: false);
      return false;
    }
    _logHeard(text, acted: true);
    _lastEngaged = DateTime.now();
    // Zastavkadan tashqari qabul qilingan gap — haqiqiy odam bor (qo'riqchi ketma-ketligi 0).
    if (!fromAttract) attractGuard.onRealSpeech();
    ref.read(voiceActivityProvider.notifier).state++; // idle-taymerga "faollik" pulsi
    // Faqat ism: oldindan yuklangan audio bilan DARHOL javob (LLM/navigatsiya kutilmaydi).
    if (content.trim().length < 2) {
      if (!onAi) {
        state = state.copyWith(answer: '', clearTable: true);
        _voiceEntryAt = DateTime.now();
        navToAi?.call();
      }
      await _speak(_labbay(), turn: t, quietMs: Env.wakeAckQuietMs);
      if (t == _turn) _followUntil = DateTime.now().add(const Duration(seconds: 15));
      return false;
    }
    // "MENI ESLAB QOL" — yuz-ro'yxat (kamera) ekrani ochiladi (1.9.36)
    if (_enrollIntent(content)) {
      await stopSpeaking();
      navTo?.call('/face-enroll');
      return true;
    }
    // OVOZLI SAHIFA-NAVIGATSIYA — faqat ANIQ "och/kir/bo'limi" buyrug'ida, JIM o'tadi.
    final route = _matchRoute(content);
    if (route != null && navTo != null && _openCmd(content)) {
      navTo!(route);
      _release(t, spoke: false);
      return true;
    }
    // AI savol. Boshqa sahifadan kelsa: eski javob tozalanadi va AI sahifaga o'tiladi —
    // savol SHU ZAHOTI yuboriladi (avval 300 ms kutilardi; sahifa intro/greet/reset
    // endi [consumeVoiceEntry]/[inQuestion] orqali javobga xalal bermaydi).
    if (!onAi) {
      state = state.copyWith(answer: '', clearTable: true);
      _voiceEntryAt = DateTime.now();
      navToAi?.call();
    }
    return _answer(content, t);
  }

  /// AI sahifasida sahifaga o'tish uchun ANIQ buyruq kerak: "…sahifasini och" va h.k.
  bool _openCmd(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r"['’ʻ`]"), '');
    return RegExp(r'\b(och|oching|ochib|ochsin|kir|kiring|kirgiz|otkazing)\b'
            r'|sahifani|sahifasini|bolimni|bolimini|bulimni'
            r'|откро|перейд|покажи страницу|\bopen\b|go to')
        .hasMatch(t);
  }

  /// Ovozli buyruq → sahifa yo'li (fuzzy, Whisper imlosiga chidamli). null = AI savol.
  String? _matchRoute(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r"['’ʻ`]"), '');
    bool has(List<String> keys) => keys.any((k) => t.contains(k));
    if (has(['noqonun', 'qonunsiz', 'egallangan', 'egalangan', 'незаконн', 'illegal']) ||
        RegExp(r'\b[ie]?g[ae]l+[aeiou]*n[aeiou]*g[aeiou]*n').hasMatch(t) ||
        RegExp(r'\bn[aeiou]*[qkg][aeiou]*n[aeiou]*n').hasMatch(t)) {
      return '/illegal';
    }
    if (has(['hujjat', 'document', 'документ', 'spravka'])) return '/docs';
    if (has(['telefon', 'phone', 'телефон', 'aloqa'])) return '/phones';
    if (has(['murojaat', 'appeal', 'обращ', 'жалоб', 'shikoyat', 'ariza topshir', 'murojat'])) return '/appeal';
    if (has(['qabul', 'rahbar', 'reception', 'прием', 'приём'])) return '/reception';
    if (has(['yangilik', 'news', 'novost', 'новост'])) return '/news';
    if (has(['ijtimoiy', 'social', 'tarmoq', 'instagram', 'telegram', 'facebook', 'youtube', 'соцсет'])) {
      return '/social';
    }
    if (has(['tuman', 'shahar', 'hudud', 'district', 'район'])) return '/districts';
    if (has(['xizmat', 'service', 'услуг'])) return '/services';
    if (has(['mulk', 'parcel', 'kadastr raqam', 'участок', 'uchastka'])) return '/property';
    if (has(['xatlov', '937'])) return '/xatlov';
    if (has(['bosh sahifa', 'asosiy', 'home', 'главн', 'orqaga'])) return '/';
    return null;
  }

  // ===== TAP-TO-TALK (qo'lda gapirish) — VAD/amplitude'siz, hamma platformada =====
  bool _manual = false;
  bool _manualStarting = false;
  int _talkSeq = 0;
  String? _manualPath;

  /// Tugmani bosib gapirish: 1-bosish boshlaydi (yozadi), 2-bosish to'xtatib AIga yuboradi.
  Future<void> toggleTalk() async {
    if (_manual) {
      await _finishTalk();
      return;
    }
    if (_manualStarting) return;
    _manualStarting = true; // ambient _capture mikrofonni to'xtatib qo'ymasin
    _takeOver(); // joriy javob/ovoz darhol to'xtaydi, ambient pauza
    try {
      if (!await _rec.hasPermission()) {
        state = state.copyWith(error: 'mic', recording: false);
        _manualStarting = false;
        _busy = false;
        return;
      }
      if (await _rec.isRecording()) await _rec.stop();
      final path = '${Directory.systemTemp.path}${Platform.pathSeparator}kadastr_talk.wav';
      await _rec.start(
          const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 16000,
              numChannels: 1,
              autoGain: true,
              noiseSuppress: true,
              echoCancel: true),
          path: path);
      _manualPath = path;
      _manual = true;
      final seq = ++_talkSeq;
      state = state.copyWith(phase: VoicePhase.listening, heard: '', recording: true, clearError: true);
      // Xavfsizlik cheki — FAQAT shu yozuv uchun (avval eski taymer keyingi yozuvni kesardi).
      Future.delayed(const Duration(seconds: 20), () {
        if (_manual && _talkSeq == seq) _finishTalk();
      });
    } catch (_) {
      _manual = false;
      _busy = false;
      state = state.copyWith(error: 'mic', recording: false);
    } finally {
      _manualStarting = false;
    }
  }

  Future<void> _finishTalk() async {
    if (!_manual) return;
    _manual = false;
    _talkSeq++;
    final t = _takeOver(); // yozuv paytida boshlangan javob bo'lsa — to'xtaydi
    state = state.copyWith(recording: false, phase: VoicePhase.transcribing);
    await _stopRec();
    final path = _manualPath;
    _manualPath = null;
    Uint8List? bytes;
    try {
      if (path != null) bytes = await File(path).readAsBytes();
    } catch (_) {}
    final text = (bytes != null) ? await _stt(bytes) : null;
    if (t != _turn) return;
    _turnEos = null;
    if (_lastSttEvent == 'sneeze') {
      await _speak(_blessYou(), turn: t);
      return;
    }
    if (text != null && text.trim().isNotEmpty) {
      final q = text.trim();
      state = state.copyWith(heard: q);
      _logHeard(q);
      _lastEngaged = DateTime.now();
      if (_enrollIntent(q)) {
        navTo?.call('/face-enroll');
        _release(t, spoke: false);
        return;
      }
      // Tugma — navigatsiya FAQAT aniq "och" buyrug'ida (JIM); aks holda AI javob beradi.
      final route = _matchRoute(q);
      if (route != null && navTo != null && _openCmd(q)) {
        navTo!(route);
        _release(t, spoke: false);
      } else {
        await _answer(q, t);
      }
    } else {
      await _speak(_repeatPrompt(), turn: t);
    }
  }

  // ===================== SAVOL → JAVOB =====================

  /// Yozilgan/bosilgan savol (AI sahifa qidiruvi, xizmat qatori) — joriy javob bekor.
  Future<void> askAI(String q) async {
    final t = _takeOver();
    _turnEos = null;
    await _answer(q, t);
  }

  /// Savolni yuboradi va javobni OQIM bilan gapiradi (0-jumla kelishi bilan ovoz).
  /// true = mazmunli javob berildi (bo'sh/topilmadi/mavzudan tashqari/bekor EMAS).
  Future<bool> _answer(String q, int t) async {
    if (t != _turn) return false;
    _busy = true;
    _qActive = true;
    _lastEngaged = DateTime.now();
    final lang = _lang;
    final eos = _turnEos;
    final sttMs = _turnSttMs;
    _turnEos = null;
    state = state.copyWith(phase: VoicePhase.thinking, suggest: false);
    // salomlashuv videosi o'ynayotgan bo'lsa to'xtaydi (ikki ovoz bo'lmasin)
    unawaited(ref.read(avatarPlayerProvider.notifier).stop().catchError((Object _) {}));
    final voice = _knownVoice();
    final ttsVoice = voice ?? 'madina';
    final ct = _turnCancel = CancelToken();
    _lastSpokenNorm = '';
    final sw = Stopwatch()..start();
    final askedAt = DateTime.now();
    _firstSoundAt = null;
    var firstAudioMs = -1, firstEventMs = -1;
    var firstClipFiller = false;
    late final AnswerSession session;
    session = AnswerSession(
      dio: _dio,
      player: _clips,
      q: q,
      lang: lang,
      voice: voice,
      useStream: !_streamUnsupported,
      onStreamUnsupported: () => _streamUnsupported = true,
      fetchTts: (text) => _fetchClip(text, ttsVoice, lang, ct),
      pickFiller: Env.fillerEnabled ? () => _pickFiller(lang, _knownVoice() ?? ttsVoice) : null,
      fillerAfter: Env.fillerEnabled ? const Duration(milliseconds: Env.fillerAfterMs) : null,
      onFirstEvent: (_) => firstEventMs = sw.elapsedMilliseconds,
      onText: (txt, {required complete, table, persona = false}) {
        if (t != _turn) return;
        _lastSpokenNorm = _normTxt(session.spokenText);
        if (complete && persona) {
          // AI o'ziga oid savol — ekranda FAQAT avatar (karta/jadval yo'q)
          state = state.copyWith(answer: '', clearTable: true);
        } else if (txt.isNotEmpty) {
          state = state.copyWith(answer: txt, table: table, clearTable: table == null);
        }
      },
      personaVideo: (text) async {
        // 1.9.47 xulqi: persona javobi uchun tayyor lab-sinx video bo'lsa — o'sha.
        if (t != _turn) return false;
        state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
        final ok = await ref.read(avatarPlayerProvider.notifier).speak(
            ref.read(avatarProvider).valueOrNull, text, lang,
            voice: ttsVoice, cachedOnly: !Env.generateSpeechVideo);
        if (t == _turn && !ok) state = state.copyWith(speaking: false);
        return ok;
      },
      onClipStart: (c) {
        if (t != _turn) return;
        if (firstAudioMs < 0) {
          firstAudioMs = sw.elapsedMilliseconds;
          firstClipFiller = c.isFiller;
        }
        _lastSpokenNorm = _normTxt(session.spokenText);
        if (!state.speaking) state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
      },
      log: _log,
    );
    _session = session;
    final res = await session.run();
    if (identical(_session, session)) _session = null;
    _lastNet = DateTime.now();
    if (t != _turn || res.cancelled) return false; // bekor qilindi — egasi boshqa
    _lastSpokenNorm = _normTxt(session.spokenText);
    final snd = _firstSoundAt;
    final soundMs = snd == null ? -1 : snd.difference(askedAt).inMilliseconds;
    final eosMs = (eos == null || snd == null) ? -1 : snd.difference(eos).inMilliseconds;
    _lat('path=${res.path} first_event_ms=$firstEventMs first_clip_ms=$firstAudioMs'
        '${firstClipFiller ? '(filler)' : ''} first_sound_ms=$soundMs total_ms=${sw.elapsedMilliseconds}'
        '${eos != null ? ' stt_ms=$sttMs eos→first_sound_ms=$eosMs' : ''}');
    if (res.text.trim().isEmpty && !session.queue.startedReal) {
      final fb = _fallback();
      state = state.copyWith(answer: fb, clearTable: true);
      await _speak(fb, turn: t);
      return false;
    }
    // video tugashi ~0.15s oldin aniqlanadi — aks-sado oynasi biroz uzunroq
    _release(t, quietMs: session.personaVideoPlayed ? Env.echoQuietMs + 600 : null);
    _maybeRetryPrime();
    return res.out['notFound'] != true && res.out['offDomain'] != true && res.text.trim().isNotEmpty;
  }

  /// Telefon ovozli pultdan kelgan buyruq (QR orqali) — wake-word shart emas.
  Future<void> handleRemoteText(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final t = _takeOver(); // ambient mikrofon pauza + joriy ovoz to'xtaydi
    state = state.copyWith(heard: q, clearError: true);
    _logHeard(q);
    final route = _matchRoute(q);
    if (route != null && navTo != null) {
      navTo!(route);
      _release(t, spoke: false); // sahifaga JIM o'tadi
      return;
    }
    if (!(onAiPage?.call() ?? false)) {
      state = state.copyWith(answer: '', clearTable: true);
      _voiceEntryAt = DateTime.now();
      navToAi?.call();
    }
    _turnEos = null;
    if (q.length >= 2) {
      await _answer(q, t);
    } else {
      await _speak(_prompt(), turn: t);
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

  /// "Meni eslab qol" — yuzni ro'yxatga olish niyati (kamera + ism so'rash).
  bool _enrollIntent(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r"['’ʻʼ`]"), '');
    return RegExp(r'(meni|мени|мене)\s*(eslab|yodda|esda|yodingda|esingda)\s*(qol|saqla|tut)'
            r'|(eslab|yodda|esda)\s*(qol|saqla)\b.*(meni|мени)'
            r'|запомни\s*меня|remember\s*me')
        .hasMatch(t);
  }

  /// QISQA matnni ovozda aytish (video'siz) — yuz-ro'yxat ekrani va h.k.
  Future<void> speakText(String text) async {
    if (_busy) return;
    final t = _takeOver();
    await _speak(text, turn: t);
  }

  /// Ism bilan chaqirilganda (savolsiz) — "Labbay! Eshitaman."
  String _labbay() => _wakeText(_lang);

  String _repeatPrompt() => {
        'uz': 'Kechirasiz, tushunmadim. Qaytadan gapiring.',
        'ru': 'Извините, я не понял. Повторите, пожалуйста.',
        'en': 'Sorry, I did not understand. Please say it again.',
      }[_lang]!;

  String _suggestPrompt() => {
        'uz': 'Kechirasiz, to‘liq tushunmadim. Quyidagi xizmatlardan birini tanlang yoki qaytadan ayting.',
        'ru': 'Извините, не совсем понял. Выберите одну из услуг ниже или повторите.',
        'en': 'Sorry, I did not quite understand. Choose one of the services below or say it again.',
      }[_lang]!;

  /// Tayyor matnni gapiradi (salom, sahifa e'loni, wake javobi, "tushunmadim"...).
  /// [video] = tayyor (keshlangan) lab-sinx video bo'lsa shuni o'ynatadi.
  /// Tugagach (yoki bekor qilinsa) [turn] bo'shatiladi.
  Future<void> _speak(String text, {required int turn, bool video = false, int? quietMs}) async {
    final t = turn;
    final clean = text.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty || t != _turn) {
      _release(t, spoke: false);
      return;
    }
    _lastSpokenNorm = _normTxt(clean);
    final lang = _lang;
    // Sovuq startda avatar-konfig ovozni uzoq ushlab turmasin (≤250 ms); wake javobi kutmaydi.
    final voice = clean == _wakeText(lang) ? (_knownVoice() ?? 'madina') : await _voiceWait(Env.avatarConfigWaitMs);
    if (t != _turn) return;
    if (video) {
      try {
        final ap = ref.read(avatarPlayerProvider.notifier);
        state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
        final ok = await ap.speak(ref.read(avatarProvider).valueOrNull, clean.substring(0, clean.length.clamp(0, 800)),
            lang,
            voice: voice, cachedOnly: !Env.generateSpeechVideo);
        if (t != _turn) return;
        if (ok) {
          _release(t, quietMs: quietMs ?? Env.echoQuietMs + 600); // video tugashi ~0.15s oldin aniqlanadi
          return;
        }
      } catch (_) {}
    }
    if (t != _turn) return;
    unawaited(ref.read(avatarPlayerProvider.notifier).stop().catchError((Object _) {}));
    final sp = clean.length > 800 ? clean.substring(0, 800) : clean;
    final (head, tail) = splitHeadTail(sp);
    final ct = _turnCancel = CancelToken();
    final q = SpeechQueue(_clips, log: _log, onClipStart: (c) {
      if (t == _turn && !state.speaking) state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
    });
    _speechQ = q;
    q.add(0, head, _fetchClip(head, voice, lang, ct));
    if (tail != null) q.add(1, tail, _fetchClip(tail, voice, lang, ct));
    q.close();
    await q.done;
    if (identical(_speechQ, q)) _speechQ = null;
    _release(t, quietMs: quietMs);
  }

  /// Jumla audiosi: oldindan keshlangan ibora bo'lsa tarmoqsiz, aks holda
  /// /tts/synthesize (dio keep-alive). Xato/bekor → null (bo'lak o'tkaziladi).
  Future<Uint8List?> _fetchClip(String text, String voice, String lang, CancelToken? ct) async {
    final cached = _phraseAudio['$lang|$voice|$text'];
    if (cached != null) return cached;
    if (text == _wakeText(lang)) return _loadPhrase(lang, voice, text);
    final timer = Stopwatch()..start();
    try {
      // Eski yo'lda (server yangilanguncha) har jumla shu yerdan: eskirgan ulanish yoki
      // 502-504 bo'lsa BIR MARTA qayta (1.9.47 UrlSource fallback'i o'rniga — o'sha yangi
      // ulanish; avval null → jumla jim tashlab ketilardi).
      final r = await withNetRetry(
          () => _dio.get<List<int>>('/tts/synthesize',
              queryParameters: {'text': text, 'voice': voice, 'lang': lang},
              cancelToken: ct,
              options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 25))),
          within: const Duration(seconds: 8));
      final d = r.data;
      if (d == null || d.length < 200) return null;
      return d is Uint8List ? d : Uint8List.fromList(d);
    } catch (_) {
      return null;
    } finally {
      _lat('tts_fetch_ms=${timer.elapsedMilliseconds} chars=${text.length}');
    }
  }

  void _logHeard(String text, {bool acted = true}) {
    // device: instansiyalarni ajratish uchun. Server acted=false MATNini saqlamaydi.
    _dio.post('/ai/heard', data: {
      'text': text,
      'lang': _lang,
      'acted': acted,
      'device': _deviceTag,
    }).then((_) {}, onError: (_) {});
  }

  static final String _deviceTag = () {
    try {
      final h = Platform.localHostname;
      return h.isNotEmpty ? h : 'kiosk';
    } catch (_) {
      return 'kiosk';
    }
  }();

  /// Qo'lda yozishni bekor qiladi (AI sahifadan chiqilganda — yozuv javobga aylanmasin).
  Future<void> cancelTalk() async {
    if (!_manual) return;
    _manual = false;
    _talkSeq++;
    _manualPath = null;
    await _stopRec();
    _turn++;
    _busy = false;
    state = state.copyWith(recording: false, phase: _on ? VoicePhase.listening : VoicePhase.off);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _startRetry?.cancel();
    _on = false;
    _turn++;
    unawaited(_session?.cancel());
    unawaited(_speechQ?.cancel());
    if (_injectedRec == null) _recInst?.dispose();
    final clips = _clipsInst;
    if (clips is AudioClipPlayer) unawaited(clips.dispose());
    super.dispose();
  }
}

final voiceProvider = StateNotifierProvider<VoiceController, VoiceUiState>((ref) => VoiceController(ref));
