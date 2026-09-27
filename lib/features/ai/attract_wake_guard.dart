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
    DateTime Function()? clock,
    this.log,
  }) : _now = clock ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _now;
  final void Function(String msg)? log;

  int _streak = 0;
  DateTime? _last;
  bool _blocked = false;

  /// Zastavka tinglash hozir o'chirilganmi (keyingi teginishgacha).
  bool get blocked => _blocked;
  int get streak => _streak;

  /// Zastavkada chaqiruv so'zi eshitildi. false = qabul qilinmaydi (o'chirilgan).
  bool onWake() {
    if (_blocked) return false;
    final now = _now();
    final last = _last;
    if (last == null || now.difference(last) > window) _streak = 0;
    _streak++;
    _last = now;
    if (_streak >= limit) {
      _blocked = true;
      log?.call('attract wake-guard: $_streak unconfirmed screensaver wakes '
          '(each ≤${window.inMinutes} min apart) — screensaver listening OFF until next touch');
    }
    return true;
  }

  /// Uyg'onishdan keyin haqiqiy nutq bo'ldi — ketma-ketlik nolga.
  void onRealSpeech() {
    _streak = 0;
    _last = null;
  }

  /// Ekranga teginish — ketma-ketlik nolga va tinglash qayta yoqiladi.
  void onTouch() {
    if (_blocked) log?.call('attract wake-guard: touch — screensaver listening ON again');
    _blocked = false;
    _streak = 0;
    _last = null;
  }
}
