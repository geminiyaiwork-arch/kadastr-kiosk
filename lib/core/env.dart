/// Environment + timing constants (from index.html + app.js).
class Env {
  static const apiBase = 'https://api.andkadastrai.uz/api/v1';
  static const apiOrigin = 'https://api.andkadastrai.uz';
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
  static const appVersion = '1.9.45';

  // Voice timing + native VAD (dBFS amplitude from `record`; tune on Windows mic)
  static const onsetDb = -38.0; // above this = speech onset
  static const stopDb = -48.0; // below this = silence
  static const onsetPollMs = 140;
  static const onsetTimeoutMs = 8000;
  static const endPollMs = 100;
  static const endSilenceMs = 750; // gap tugashi (tezroq javob; 900 dan tushirildi — 2026-08-02)
  static const utteranceMaxMs = 22000;
  static const minVoicedMs = 150;
  static const armedMs = 18000;
}

/// Supported languages.
const kLangs = ['uz', 'ru', 'en'];
