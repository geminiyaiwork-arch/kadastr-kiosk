/// Environment + timing constants (from index.html + app.js).
class Env {
  static const apiBase = 'https://api.andkadastrai.uz/api/v1';
  static const apiOrigin = 'https://api.andkadastrai.uz';
  static const kioskId = 1;

  // Fixed design canvas (portrait), uniform-scaled + letterboxed.
  static const canvasW = 1080.0;
  static const canvasH = 1920.0;

  // Idle behaviour
  static const resetSec = 90; // idle -> home + uz
  static const attractSec = 120; // idle -> screensaver
  static const heartbeatMs = 60000;

  // App version (reported via heartbeat; keep in sync with pubspec).
  static const appVersion = '1.6.1';

  // Voice timing + native VAD (dBFS amplitude from `record`; tune on Windows mic)
  static const onsetDb = -38.0; // above this = speech onset
  static const stopDb = -48.0; // below this = silence
  static const onsetPollMs = 140;
  static const onsetTimeoutMs = 8000;
  static const endPollMs = 100;
  static const endSilenceMs = 1800;
  static const utteranceMaxMs = 22000;
  static const minVoicedMs = 150;
  static const armedMs = 18000;
}

/// Supported languages.
const kLangs = ['uz', 'ru', 'en'];
