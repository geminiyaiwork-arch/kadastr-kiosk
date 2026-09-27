/// ZASTAVKA-UYG'OTISH QO'RIQCHISI — zastavka videosida ovoz bor: kiosk o'z videosidagi
/// "Alomat"ni eshitib o'zini qayta-qayta uyg'otmasin.
///
/// Zastavkada har bir uyg'onish "tasdiqlanmagan" hisoblanadi, toki undan keyin HAQIQIY
/// nutq (zastavkadan tashqarida qabul qilingan gap) yoki ekranga teginish bo'lmaguncha.
/// Tasdiqlanmagan uyg'onishlar ketma-ket [limit] marta (har biri oldingisidan
/// [window] ichida) bo'lsa — zastavka tinglash KEYINGI TEGINISHGACHA o'chiriladi.
///
/// Eslatma: zastavka har uyg'onishdan keyin ~330s (Env.attractSec) da qaytadi, shuning
/// uchun 3 ta uyg'onish hech qachon bitta 10 daqiqalik oynaga sig'maydi (≥660s). Shu
/// sababli oyna ketma-ket uyg'onishlar ORASIDAGI masofaga qo'llanadi.
class AttractWakeGuard {
  AttractWakeGuard({
    this.limit = 3,
    this.window = const Duration(minutes: 10),
    this.blockFor = const Duration(minutes: 30),
    DateTime Function()? clock,
    this.log,
  }) : _now = clock ?? DateTime.now;

  final int limit;
  final Duration window;

  /// Blok o'zi shuncha vaqtdan keyin tugaydi (teginish bo'lmasa ham).
  final Duration blockFor;
  final DateTime Function() _now;
  final void Function(String msg)? log;

  int _streak = 0;
  DateTime? _last;
  DateTime? _blockedUntil;

  /// Zastavka tinglash hozir o'chirilganmi (keyingi teginishgacha yoki [blockFor] o'tguncha).
  bool get blocked {
    final u = _blockedUntil;
    if (u == null) return false;
    if (!_now().isBefore(u)) {
      log?.call('attract wake-guard: block expired after ${blockFor.inMinutes} min — screensaver listening ON');
      _blockedUntil = null;
      _streak = 0;
      _last = null;
      return false;
    }
    return true;
  }
  int get streak => _streak;

  /// Zastavkada chaqiruv so'zi eshitildi. false = qabul qilinmaydi (o'chirilgan).
  bool onWake() {
    if (blocked) return false;
    final now = _now();
    final last = _last;
    if (last == null || now.difference(last) > window) _streak = 0;
    _streak++;
    _last = now;
    if (_streak >= limit) {
      _blockedUntil = now.add(blockFor);
      log?.call('attract wake-guard: $_streak unconfirmed screensaver wakes '
          '(each ≤${window.inMinutes} min apart) — screensaver listening OFF until next touch '
          '(max ${blockFor.inMinutes} min)');
    }
    return true;
  }

  /// Uyg'onishdan keyin haqiqiy nutq bo'ldi (yoki uyg'onish gapidagi savolga mazmunli
  /// javob berildi) — ketma-ketlik nolga.
  void onRealSpeech() {
    _streak = 0;
    _last = null;
  }

  /// Ekranga teginish — ketma-ketlik nolga va tinglash qayta yoqiladi.
  void onTouch() {
    if (_blockedUntil != null) log?.call('attract wake-guard: touch — screensaver listening ON again');
    _blockedUntil = null;
    _streak = 0;
    _last = null;
  }
}
