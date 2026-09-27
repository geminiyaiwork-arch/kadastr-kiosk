/// Environment + timing constants (from index.html + app.js).
class Env {
  // --dart-define=KIOSK_API_ORIGIN=http://127.0.0.1:8787 — lokal mock-server bilan sinash uchun
  // (tool/mock_voice_server.dart). Standart = jonli server.
  static const apiOrigin = String.fromEnvironment('KIOSK_API_ORIGIN', defaultValue: 'https://api.andkadastrai.uz');
  static const apiBase = '$apiOrigin/api/v1';
  static const portalOrigin = 'https://andkadastrai.uz'; // screensaver video shu yerdan
  static const kioskId = 1;

  // Fixed design canvas (portrait), uniform-scaled + letterboxed.
  static const canvasW = 1080.0;
  static const canvasH = 1920.0;

  // Idle behaviour — 5 daqiqa ishlatilmasa asosiy menyuga qaytadi (band bo'lса — otmaydi)
  static const resetSec = 300; // idle -> home + uz (5 daqiqa)
  static const attractSec = 330; // idle -> screensaver (bosh menyudan 30s keyin)
  static const heartbeatMs = 60000;

  // App version (reported via heartbeat; keep in sync with pubspec).
  // ⚠️ MUHIM: pubspec.yaml `version:` BILAN BIRGA oshir — aks holda avto-yangilanish
  // manifestдан «yangi» ko'rib cheksiz qayta-o'rnatadi + admin/versiya-barда eski ko'rinadi.
  static const appVersion = '1.9.47';

  // Voice timing + native VAD (dBFS amplitude from `record`; tune on Windows mic)
  static const onsetDb = -38.0; // above this = speech onset
  static const stopDb = -48.0; // below this = silence
  static const onsetPollMs = 140;
  static const onsetTimeoutMs = 8000;
  static const endPollMs = 100;
  static const endSilenceMs = 600; // 120 ms polling bilan 5 sukut namunasi; kioskda pauzali nutqni tekshiring
  // Tez ovoz: tayyor avatar videosi ishlaydi, yangi video javobni ushlab turmaydi.
  static const generateSpeechVideo = false;
  static const avatarConfigWaitMs = 250;

  // ---- Oqimli javob (/ai/chat-stream) + "filler" (1.9.48) ----
  // Savol yuborilgach shu vaqt ichida hech qanday javob audiosi kelmasa — qisqa
  // tayyor ibora ("Bir soniya.") aytiladi; haqiqiy javob u tugashi bilan boshlanadi.
  static const fillerEnabled = true;
  static const fillerAfterMs = 1100;
  // AI gapirib bo'lgач shu vaqt ichida NUTQ BOSHI sanalmaydi (TTS dumi/reverb o'zini
  // uyg'otmasin). Mikrofon esa DARHOL yozishni boshlaydi (yangi savol boshi yo'qolmaydi).
  // Avval 3000 ms edi — foydalanuvchi javobdan keyin darhol gapirsa gap boshi kesilardi.
  static const echoQuietMs = 900;
  static const wakeAckQuietMs = 350; // "Labbay! Eshitaman." dan keyin — odam darhol gapiradi
  // Matnli aks-sado filtri faqat nutq shu vaqt ichida boshlangan bo'lsa qo'llanadi.
  static const echoWindowMs = 3000;
  static const utteranceMaxMs = 22000;
  static const minVoicedMs = 150;
  static const armedMs = 18000;
}

/// Supported languages.
const kLangs = ['uz', 'ru', 'en'];
