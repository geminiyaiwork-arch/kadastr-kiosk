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
import '../../core/services/avatar_player.dart';
import '../../router.dart';

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

  VoiceUiState copyWith(
          {VoicePhase? phase,
          String? heard,
          String? answer,
          List<List<dynamic>>? table,
          bool? speaking,
          bool? recording,
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
        error: clearError ? null : (error ?? this.error),
      );
}

/// Wake-word variants for "KAI" (= Kadastr AI), incl. Whisper mis-hearings.
const _wakeSet = {
  'kai', 'kayi', 'kay', 'kei', 'key', 'kaye', 'kayy', 'kayu', 'kae', 'kya', 'kyi', 'keyi',
  'kaii', 'kaiy', 'kaey', 'kaya', 'khai', 'khay', 'kaj', // qo'shimcha Whisper variantlari
  'qai', 'qei', 'qey', 'qaii', // 'qayi' OLIB TASHLANDI — o'zbekcha "qay(si)" so'zi bilan chalkashardi (jonli: "qayi, non")
  'кай', 'кей', 'кэй', 'кайи', 'каи', 'кая', 'каий', 'кайй',
  'kadastr', 'cadastre', 'kadaster', 'kadastir', // imlo variantlari (startsWith ham ushlaydi)
};

// Fuzzy-moslik O'CHIRILDI: 'qo'y/qay/gey' kabi oddiy so'zlar ism deb olinardi.
bool _wakeFuzzy(String w) => false;

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
  DateTime _lastRepeat = DateTime.fromMillisecondsSinceEpoch(0);
  // KAI gapirganidan keyingi "suhbat oynasi" — shu vaqtgacha AI sahifasida
  // ismsiz davom-savoli qabul qilinadi
  DateTime _followUntil = DateTime.fromMillisecondsSinceEpoch(0);
  // AI gapirgandan keyin ECHO-SUKUT: mikrofon o'z ovozini (TTS tail/reverb) qayta eshitib
  // soxta "kadastr" wake bermasin (aks holda bo'sh turганда o'zidan AI'ga kirib ketardi,
  // zastavka chiqmasdi). Shu vaqtgacha ambient tinglash O'CHIQ.
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

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

  /// Gapirishни (TTS + avatar video) DARHOL to'xtatadi — sahifa almashса yoki zastavka
  /// chiqганда fonда ovoz qolmasin. Ambient tinglash o'chmaydi (faqat joriy ovoz to'xtaydi).
  Future<void> stopSpeaking() async {
    try { await _player.stop(); } catch (_) {}
    try { await ref.read(avatarPlayerProvider.notifier).stop(); } catch (_) {}
    _busy = false;
    _quietUntil = DateTime.now().add(const Duration(milliseconds: 800));
    if (state.speaking) state = state.copyWith(speaking: false);
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

  /// AI sahifasiga qayta kirilganda ESKI javob/jadval tozalanadi —
  /// avatar to'liq ekranda salomlashadi (eski karta ustida emas).
  void resetConversation() {
    state = state.copyWith(answer: '', heard: '', clearTable: true);
  }

  /// Speak a greeting / prompt (used when entering the AI page or on wake-only).
  Future<void> greet(String text) async {
    if (_busy) return;
    _busy = true;
    await _speak(text, video: true); // salomlashuv — muloqat → video generatsiya
  }

  /// Foydalanuvchi QO'LDA (tugma bilan) sahifa ochganда — o'sha sahifани OVOZда
  /// tanishtiradi. (Ovozli navigatsiya JIM o'tadi; bu FAQAT manual bosishда
  /// chaqiriladi.) Content sahifада avatar yo'q → oddiy TTS (video emas).
  Future<void> announcePage(String route) async {
    if (_busy) return; // allaqachon gapiryapti — bezovta qilmaymiz
    final intro = _pageIntro(route);
    if (intro == null || intro.isEmpty) return;
    _busy = true;
    await _speak(intro, video: false);
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
      } else if ((onAiPage?.call() ?? false) &&
          text != null &&
          _stripWake(text) != null &&
          DateTime.now().difference(_lastRepeat).inSeconds >= 20) {
        // AI sahifasida TUSHUNARSIZ gap — qaytadan so'raymiz (20s cooldown:
        // fon shovqinida har 3.6s "tushunmadim" spam bo'lmasin)
        _lastRepeat = DateTime.now();
        await _speak(_repeatPrompt(), video: false);
      } else {
        _busy = false;
      }
    }
  }

  // Ambient tinglash — DINAMIK OYNA (gap tugashini kutadi, avval qat'iy 3.6s edi →
  // "Marhamat tumani statistikasi" kabi uzun savollarni KESIB/BO'LIB yuborardi).
  // Windows: getAmplitude bilan onset→sukut endpointing (to'liq gapni yozadi).
  // Linux: getAmplitude o'lik (-160) → ESKI qat'iy oynaga qaytadi (biroz uzunroq).
  static const int _winMs = 5000;             // Linux fallback qat'iy oyna
  static const int _pollMs = 120;             // amplituda tekshiruv qadami
  static const int _preOnsetMaxMs = 4200;     // gap boshlanishini kutish (ambient tez javob bersin)
  static const int _maxUttMs = 11000;         // eng uzun gap (uzun savol ham sig'sin)
  static const double _rmsMinDbfs = -48.0;    // muvozanat: user ovozi yutilmasin, uzoq shovqin ham kirmasin
  Future<String?> _capture() async {
    // ECHO-SUKUT: AI endigina gapirgan bo'lsa, o'z ovozini (tail/reverb) eshitmaslik uchun
    // qisqa muddat tinglamaymiz (soxta wake -> o'zidan AI'ga kirish oldini oladi).
    if (DateTime.now().isBefore(_quietUntil)) { await _sleep(250); return null; }
    final path = '${Directory.systemTemp.path}/kadastr_utt.wav';
    try {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    } catch (_) {
      await _sleep(600);
      return null;
    }
    var waited = 0, spoken = 0, silence = 0;
    var ampAlive = false, onset = false;
    while (_on && !_busy) {
      await _sleep(_pollMs);
      waited += _pollMs;
      if (_manual) return null; // tap-to-talk boshlandi → mikrofon unga tegishli
      double db = -160;
      try { db = (await _rec.getAmplitude()).current; } catch (_) {}
      if (db > -120) ampAlive = true; // Linux -160 qaytaradi → o'lik deb bilamiz

      if (!ampAlive) {
        // Amplituda yo'q (Linux) → eski qat'iy oyna xulqi
        if (waited >= _winMs) break;
        continue;
      }
      if (!onset) {
        if (db > Env.onsetDb) { onset = true; spoken = 0; silence = 0; }   // gap boshlandi
        else if (waited >= _preOnsetMaxMs) { break; }                      // gap yo'q → sukut
      } else {
        spoken += _pollMs;
        if (db < Env.stopDb) {
          silence += _pollMs;
          if (silence >= Env.endSilenceMs) break;                          // gap tugadi (sukut cho'zildi)
        } else {
          silence = 0;                                                     // yana gapiryapti
        }
        if (spoken >= _maxUttMs) break;                                    // xavfsizlik cheki
      }
    }
    // Tap-to-talk boshlangan bo'lsa mikrofon ENDI unga tegishli — to'xtatib qo'ymaymiz
    if (_manual) return null;
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
        data: Stream.fromIterable([bytes]), // BUTUN bayt bir bo'lakda (avval bayt-bayt = 350k+ mikro-hodisa, sekin)
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
    if (_lang == 'ru') return cyr >= 2 && foreign <= cyr;
    // uz/en: STT lotin yozadi; kirill USTUN kelsa — buzuq eshitish (ruscha javob chiqmasin)
    return latin >= 2 && foreign <= latin && cyr <= latin;
  }

  /// Find wake word in the first 3 tokens. null=no wake, ''=wake only, 'cmd'=wake+command.
  String? _stripWake(String text) {
    final low = text.toLowerCase().replaceAll(RegExp(r"['’`ʻʼ.,!?:;]"), '').trim();
    if (low.isEmpty) return null;
    final words = low.split(RegExp(r'\s+'));
    var wi = -1;
    for (var i = 0; i < min(3, words.length); i++) {
      final w = words[i];
      if (_wakeSet.contains(w) ||
          w.startsWith('kadastr') ||
          w.startsWith('кадастр') ||
          w.startsWith('cadastre') ||
          _wakeFuzzy(w)) {
        wi = i;
        break;
      }
    }
    if (wi < 0) return null;
    // "Kadastr AI" ikki so'z — ism DAVOMI ('ai/ey/аи') ham tashlanadi,
    // aks holda "Kadastr AI" wake-only o'rniga content='ai' bo'lib qolardi
    var j = wi + 1;
    const tail = {'ai', 'ay', 'ey', 'eyi', 'ei', 'аи', 'ай', 'ии'};
    while (j < words.length && tail.contains(words[j])) {
      j++;
    }
    return words.sublist(j).join(' ').replaceAll(RegExp(r'^[\s,.:;!?"()\-—]+'), '').trim();
  }

  Future<void> _handle(String text) async {
    state = state.copyWith(heard: text);
    final onAi = onAiPage?.call() ?? false;
    // BOSHQA sahifalarda faqat ISM bilan qabul qilinadi ("Kadastr AI ..." / "KAI ...") —
    // atrofdagi begona suhbat AI'ni ishga tushirmaydi.
    // AI SAHIFASIDA esa ism SHART EMAS (web-kiosk pariteti, directOnAi): foydalanuvchi
    // AI ekraniga o'zi kirgan — savol (≥6 belgi) darhol qabul qilinadi. Avval har gapga
    // "Kadastr AI" talab qilinardi → birinchi savol tashlab yuborilib, "sekin javob
    // beryapti" his qilinardi. Echo-himoya: _quietUntil (2.5s) + _busy + _valid saqlanadi.
    final cmd = _stripWake(text);
    String content;
    if (cmd != null) {
      content = cmd;
    } else if (onAi &&
        (DateTime.now().isBefore(_followUntil) || text.trim().length >= 6)) {
      content = text; // AI sahifasida ismsiz savol / follow-up
      _followUntil = DateTime.fromMillisecondsSinceEpoch(0); // qayta uzaymaydi
    } else {
      _logHeard(text, acted: false); // eshitildi, lekin ism yo'q — E'TIBORSIZ
      _busy = false;
      return;
    }
    _logHeard(text, acted: true);
    ref.read(voiceActivityProvider.notifier).state++; // idle-taymerga "faollik" pulsi
    // 1) OVOZLI SAHIFA-NAVIGATSIYA — sahifaga JIM o'tadi (AI faqat AI sahifasida
    //    gapiradi — boshqa sahifalarda ovozli izoh YO'Q).
    //    AI sahifasida faqat aniq "och/sahifasini och" buyrug'ida o'tadi.
    final route = _matchRoute(content);
    // NAVIGATSIYA endi HAR sahifada ANIQ "och/kir/bo'limi" buyrug'ini talab qiladi.
    // (Avval bosh ekranда och-buyrug'isiz sakrardi → mikrofon "kadastr raqami"/echo
    //  eshitib O'ZIDAN O'ZI Telefonlarга o'tib ketardi. Endi faqat "telefonlarni och" da.)
    if (route != null && navTo != null && _openCmd(content)) {
      navTo!(route);
      _busy = false;
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
      // "Kadastr AI" (yolg'iz ism) — "Hoy, labbay! Eshitaman..." deb javob beramiz va
      // KEYINGI gap 15 soniya ichida ISMSIZ qabul qilinadi (bir martalik)
      _followUntil = DateTime.now().add(const Duration(seconds: 15));
      await _speak(_labbay(), video: false);
    }
  }

  /// AI sahifasida sahifaga o'tish uchun ANIQ buyruq kerak: "…sahifasini och",
  /// "…bo'limini ochib ber", "…ga o't". Oddiy savol bo'lsa — navigatsiya YO'Q.
  bool _openCmd(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r"['’ʻ`]"), '');
    // FAQAT to'liq buyruq-so'zlar (\b ikkala tomonda) — "ochiq/otkazilgan/bolimi" kabi
    // oddiy so'zlar buyruq deb qabul qilinMAYDI (aks holda savol sahifaga uloqtirardi).
    return RegExp(r'\b(och|oching|ochib|ochsin|kir|kiring|kirgiz|otkazing)\b'
            r'|sahifani|sahifasini|bolimni|bolimini|bulimni'
            r'|откро|перейд|покажи страницу|\bopen\b|go to')
        .hasMatch(t);
  }

  /// Ovozli buyruq → sahifa yo'li (fuzzy, Whisper imlosiга chidamli). null = AI savol.
  String? _matchRoute(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r"['’ʻ`]"), '');
    bool has(List<String> keys) => keys.any((k) => t.contains(k));
    // noqonuniy egallangan yerlar — aniq so'z + fuzzy undosh-skeleton (nakanuni/egellengen…).
    // Skeletonlar SO'Z BOSHIga bog'langan (\b) — aks holda "belgilangan/olinganini" kabi
    // oddiy so'zlar ham mos tushib, savolni /illegal sahifasiga uloqtirardi.
    if (has(['noqonun', 'qonunsiz', 'egallangan', 'egalangan', 'незаконн', 'illegal']) ||
        RegExp(r'\b[ie]?g[ae]l+[aeiou]*n[aeiou]*g[aeiou]*n').hasMatch(t) ||
        RegExp(r'\bn[aeiou]*[qkg][aeiou]*n[aeiou]*n').hasMatch(t)) {
      return '/illegal';
    }
    if (has(['hujjat', 'document', 'документ', 'spravka'])) return '/docs';
    if (has(['telefon', 'phone', 'телефон', 'aloqa'])) return '/phones'; // 'raqam' OLINDI — "kadastr raqami" telefon EMAS
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
  String? _manualPath;

  /// Tugmani bosib gapirish: 1-bosish boshlaydi (yozadi), 2-bosish to'xtatib AIга
  /// yuboradi. Linux'da getAmplitude ishlamaydi → VAD o'rniga shu ishlatiladi.
  Future<void> toggleTalk() async {
    if (_manual) {
      await _finishTalk();
      return;
    }
    _busy = true; // ambient loop'ni pauza qiladi (mikrofon to'qnashmasin)
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await ref.read(avatarPlayerProvider.notifier).stop(); // o'ynayotgan avatar-videoni darhol to'xtat
    } catch (_) {}
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
      Future.delayed(const Duration(seconds: 20), () {
        if (_manual) _finishTalk();
      }); // xavfsizlik cheki
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
      // Tugma AI sahifasida — navigatsiya FAQAT aniq "och" buyrug'ida (JIM o'tadi);
      // aks holda AI javob beradi. Tugma orqali ISM shart emas.
      final route = _matchRoute(text.trim());
      if (route != null && navTo != null && _openCmd(text.trim())) {
        navTo!(route);
        _busy = false;
      } else {
        await askAI(text.trim());
      }
    } else {
      // Tushunarsiz — avatar to'liq ekranda qoladi (karta chiqarilmaydi), faqat ovozda so'raydi
      await _speak(_repeatPrompt(), video: false);
    }
  }

  Future<void> askAI(String q) async {
    _busy = true;
    state = state.copyWith(phase: VoicePhase.thinking);
    String answer = '';
    List<List<dynamic>>? table;
    bool persona = false;
    try {
      final r = await _dio.post('/ai/chat', data: {'q': q, 'lang': _lang});
      final m = Map<String, dynamic>.from(r.data as Map);
      answer = (m['text'] ?? '').toString();
      persona = m['persona'] == true;
      if (m['table'] is List && (m['table'] as List).isNotEmpty) {
        table = (m['table'] as List).map((e) => (e as List).cast<dynamic>()).toList();
      }
    } catch (_) {}
    if (answer.trim().isEmpty) answer = _fallback();
    if (persona) {
      // AI o'ziga oid savol ("isming nima" ...) — ekranda FAQAT avatar qoladi (karta/jadval yo'q)
      state = state.copyWith(answer: '', clearTable: true);
    } else {
      state = state.copyWith(answer: answer, table: table, clearTable: table == null);
    }
    // persona (muloqat) → video generatsiya; ma'lumot → karta + TTS
    await _speak(answer, video: persona);
  }

  /// Telefon ovozli pultдан kelgan buyruq (QR orqali) — wake-word shart emas, to'g'ridan-to'g'ri bajaradi.
  Future<void> handleRemoteText(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    _busy = true; // ambient mikrofonni pauza qiladi (to'qnashmasin)
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await ref.read(avatarPlayerProvider.notifier).stop(); // o'ynayotgan avatar-videoni darhol to'xtat
    } catch (_) {}
    state = state.copyWith(heard: q, clearError: true);
    _logHeard(q);
    final route = _matchRoute(q);
    if (route != null && navTo != null) {
      navTo!(route);
      _busy = false; // sahifaga JIM o'tadi (ovoz faqat AI sahifasida)
      return;
    }
    navToAi?.call();
    await _sleep(250);
    if (q.length >= 2) {
      await askAI(q);
    } else {
      await _speak(_prompt(), video: false);
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

  /// Ism bilan chaqirilganda (savolsiz) — "Labbay, eshitaman!" deb javob beradi.
  String _labbay() => {
        'uz': 'Hoy, labbay! Eshitaman, savolingizni ayting.',
        'ru': 'Да, слушаю вас! Задавайте ваш вопрос.',
        'en': 'Yes, I am listening! Please ask your question.',
      }[_lang]!;

  String _repeatPrompt() => {
        'uz': 'Kechirasiz, tushunmadim. Qaytadan gapiring.',
        'ru': 'Извините, я не понял. Повторите, пожалуйста.',
        'en': 'Sorry, I did not understand. Please say it again.',
      }[_lang]!;

  /// [video] = MULOQAT javobi (salom/persona/prompt) → LAB-SINXRON video generatsiya.
  /// Ma'lumotli javoblarda `false` (avatar burchakda statik + karta, ovoz TTS).
  Future<void> _speak(String text, {bool video = false}) async {
    final clean = text.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) {
      _busy = false;
      return;
    }
    // POYGA-FIX: birinchi salomlashuvda avatar-konfig hali yuklanmagan bo'ladi
    // (ikkalasi bir soniyada boshlanadi) -> null deb video o'tkazib yuborilardi.
    // Qisqa kutamiz — konfig kelsa video, kelmasa oddiy ovoz.
    var avCfg = ref.read(avatarProvider).valueOrNull;
    if (avCfg == null) {
      try {
        avCfg = await ref.read(avatarProvider.future).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    final voice = (avCfg?.male ?? false) ? 'sardor' : 'madina';
    // 1) JONLI AVATAR (FAQAT muloqat/persona/salomlashuv savollarida): gapirganda
    //    LAB-SINXRON video generatsiya qilinadi (ovoz ham ichida), jim turganda oddiy
    //    rasm. Muvaffaqiyatда oddiy TTS chalinmaydi (ikki ovoz bo'lmasin). Ma'lumotli
    //    javobda video YO'Q — avatar burchakda, karta ko'rinadi, javob TTS'da.
    if (video) {
      try {
        final ap = ref.read(avatarPlayerProvider.notifier);
        state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
        final ok = await ap.speak(avCfg, clean.substring(0, min(clean.length, 800)), _lang, voice: voice);
        if (ok) {
          state = state.copyWith(speaking: false);
          _quietUntil = DateTime.now().add(const Duration(milliseconds: 2500)); // echo-sukut
          _busy = false;
          return;
        }
        // video bo'lmadi — pastdagi oddiy TTS'ga tushamiz
      } catch (_) {}
    }
    // TTS yo'liga tushdik (ma'lumotli javob YOKI video muvaffaqiyatsiz) — o'ynayotgan
    // avatar-video qolgan bo'lsa to'xtatamiz (ovoz ustma-ust tushmasin, burchakда eski video qolmasin).
    try {
      await ref.read(avatarPlayerProvider.notifier).stop();
    } catch (_) {}
    final url = '${Env.apiBase}/tts/synthesize?text=${Uri.encodeComponent(clean.substring(0, min(clean.length, 800)))}'
        '&voice=$voice&lang=$_lang';
    // ignore: avoid_print
    print('[tts] speak boshlanyapti (${clean.length} belgi)');
    state = state.copyWith(phase: VoicePhase.speaking, speaking: true);
    try {
      await _player.stop();
      // MUHIM: onPlayerComplete.first.timeout(onTimeout:...) ISHLATILMAYDI —
      // audioplayers'da runtime tip-xatosi beradi (Future<AudioEvent> vs () => Null)
      // va ovoz UMUMAN chalinmasdi. Future.any tip-xavfsiz: tugash hodisasi YOKI
      // matn uzunligiga mos cap-vaqt (800 belgi ≈ 50-70s) — qaysi biri avval.
      final capSec = 15 + (clean.length ~/ 10);
      final done = _player.onPlayerComplete.first;
      await _player.play(UrlSource(url));
      await Future.any<void>([done, Future<void>.delayed(Duration(seconds: capSec))]);
      try {
        await _player.stop();
      } catch (_) {} // cap'da to'xtatiladi (o'z ovozini eshitmasin)
    } catch (e) {
      // Ovoz chalinmasa sababи konsolда ko'rinsin (jim yutilib ketmasin)
      // ignore: avoid_print
      print('[tts] play xato: $e');
    }
    state = state.copyWith(speaking: false);
    _quietUntil = DateTime.now().add(const Duration(milliseconds: 2500)); // echo-sukut (o'z ovozini eshitmasin)
    _busy = false;
  }

  void _logHeard(String text, {bool acted = true}) {
    // device: instansiyalarni ajratish uchun (dev-mashina vs jonli kiosk). Server acted=false
    // (ismsiz ambient nutq) MATNini saqlamaydi — faqat uzunlik; maxfiylik (#14).
    _dio.post('/ai/heard', data: {
      'text': text, 'lang': _lang, 'acted': acted, 'device': _deviceTag,
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

  @override
  void dispose() {
    _on = false;
    _rec.dispose();
    _player.dispose();
    super.dispose();
  }
}

final voiceProvider = StateNotifierProvider<VoiceController, VoiceUiState>((ref) => VoiceController(ref));
