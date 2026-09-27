import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../env.dart';
import '../../features/ai/voice_controller.dart';
import '../../router.dart';

/// Kiosk avto-yangilanish manifesti (portal). Format: {"version":"1.6.1","exe":"https://.../setup.exe","notes":"..."}
const _kUpdateUrl = 'https://andkadastrai.uz/kiosk-latest.json';

/// Kiosk AVTO-yangilanish: nazoratsiz qurilma bo'lgani uchun HECH KIMDAN SO'RAMASDAN
/// o'zini yangilaydi. Yangi versiya topilsa (manifest version > Env.appVersion), band
/// bo'lmagan (video/murojaat yozilmayotgan / zastavkada) paytда jim yuklab, sokin o'rnatib,
/// dastur o'zini qayta ochadi. Band bo'lsa — o'rnatmaydi, keyingi tekshiruvда qayta urinadi.
class UpdateService {
  static bool _busy = false;
  // Loop-guard: bir versiyani sessiyada 3 martadan ortiq o'rnatishga urinmaymiz.
  // (Versiya desinxron bo'lsa yoki o'rnatish muvaffaqiyatsiz bo'lsa — har 15 daqiqada
  //  cheksiz qayta-o'rnatish loopiga tushmaslik uchun.)
  static String _attemptedVer = '';
  static int _attemptCount = 0;

  /// [canInstall] — hozir o'rnatsa bo'ladimi (faol foydalanuvchini uzmaslik uchun).
  /// null yoki true qaytarsa darhol o'rnatadi; false qaytarsa — bu safar o'tkazadi.
  static Future<void> check({bool Function()? canInstall, Future<void> Function()? beforeInstall}) async {
    if ((!Platform.isWindows && !Platform.isLinux) || _busy) return;
    String latest = '', exe = '', deb = '';
    bool enabled = true;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
      final r = await dio.get(_kUpdateUrl);
      final m = Map<String, dynamic>.from(r.data is Map ? r.data : (r.data is String ? {} : {}));
      latest = (m['version'] ?? '').toString().trim();
      exe = (m['exe'] ?? '').toString().trim();
      deb = (m['deb'] ?? '').toString().trim();
      enabled = m['enabled'] != false; // admin avto-yangilanishni o'chirsa (false) — to'xtaymiz
    } catch (_) {
      return;
    }
    if (!enabled) return; // admin panelдан o'chirilgan
    final pkgUrl = Platform.isWindows ? exe : deb;
    if (latest.isEmpty || pkgUrl.isEmpty || !_newer(latest, Env.appVersion)) return;
    // Loop-guard: shu versiyani 3 marta urinib bo'lgan bo'lsak — boshqa urinmaymiz.
    if (latest == _attemptedVer && _attemptCount >= 3) return;
    // Faol foydalanuvchini uzmaslik: band bo'lsa (murojaat/video) hozir o'rnatmaymiz —
    // keyingi (15 daqiqalik) tekshiruv yoki zastavkaga o'tganda o'rnatadi.
    if (canInstall != null && !canInstall()) return;
    if (latest == _attemptedVer) { _attemptCount++; } else { _attemptedVer = latest; _attemptCount = 1; }
    await _install(pkgUrl, latest, canInstall: canInstall, beforeInstall: beforeInstall);
  }

  /// a > b (X.Y.Z semver taqqoslash)
  static bool _newer(String a, String b) {
    List<int> parts(String s) => s.split(RegExp(r'[.+\-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  static Future<void> _install(String pkgUrl, String v,
      {bool Function()? canInstall, Future<void> Function()? beforeInstall}) async {
    _busy = true;
    var dialogShown = false;
    var windowChanged = false;
    try {
      final tmp = Platform.isWindows
          ? '${Directory.systemTemp.path}\\kadastr-kiosk-setup-$v.exe'
          : '${Directory.systemTemp.path}/kadastr-kiosk-$v.deb';
      // 1) JIM yuklab olish — dialog YO'Q (avval "o'rnatilmoqda" oynasi yuklash davomida,
      //    ≤15 daqiqa, ekranni to'sib turardi).
      await Dio().download(pkgUrl, tmp, options: Options(receiveTimeout: const Duration(minutes: 15)));
      // Yuklab olingan fayl BUTUNLIGI: yarim/buzuq yuklansa o'rnatgichni ISHGA TUSHIRMAYMIZ
      // (aks holda exit(0) qilib kioskни o'lik qoldirardi). Setup ~20MB → <3MB = buzuq.
      if (await File(tmp).length() < 3 * 1024 * 1024) throw Exception('paket fayli buzuq/yarim yuklandi');
      // 2) Yuklash davomida odam kelgan bo'lishi mumkin — QAYTA tekshiramiz (1.9.48).
      //    Hozir mumkin bo'lmasa — bu urinish hisoblanmaydi, keyingi tekshiruvda qaytadan.
      if (canInstall != null && !canInstall()) {
        if (_attemptCount > 0) _attemptCount--;
        _busy = false;
        return;
      }
      // 3) Ovoz/mikrofon to'xtaydi — o'rnatish paytida gapirmasin/tinglamasin.
      try {
        await beforeInstall?.call();
      } catch (_) {}
      // So'ramaymiz, lekin ekranda qisqa "Yangilanmoqda…" ko'rsatamiz (fuqaro tushunsin).
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        dialogShown = true;
        showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(width: 22),
                Flexible(child: Text('Yangi versiya o‘rnatilmoqda…', style: TextStyle(fontSize: 18))),
              ]),
            ),
          ),
        );
      }
      // MUHIM: UAC (ruxsat) oynasi TO'LIQ-EKRAN kiosk ORQASIDA qolib, yangilanish
      // hech qachon boshlanmasdi! O'rnatishdan oldin kiosk kichrayadi — UAC ko'rinadi.
      try {
        windowChanged = true;
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setFullScreen(false);
        await windowManager.minimize();
      } catch (_) {}
      if (Platform.isWindows) {
        // /SILENT: kichik jarayon-oynasi ko'rinadi; [Run] postinstall kioskни QAYTA ochadi.
        await Process.start(tmp, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
            mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 1));
        exit(0); // dastur o'zini yopadi — o'rnatgich davom etadi
      } else {
        // LINUX: pkexec (grafik parol-oyna) bilan o'rnatamiz, so'ng yangi versiyani ishga
        // tushirib, o'zimizni yopamiz.
        final r = await Process.run('pkexec', ['dpkg', '-i', tmp]);
        if (r.exitCode == 0) {
          await Process.start('/usr/bin/kadastr-kiosk', [], mode: ProcessStartMode.detached);
          await Future.delayed(const Duration(milliseconds: 500));
          exit(0);
        }
        throw Exception('dpkg ${r.exitCode}');
      }
    } catch (_) {
      _busy = false;
      final c = rootNavigatorKey.currentContext;
      if (dialogShown && c != null && c.mounted) Navigator.of(c, rootNavigator: true).maybePop();
      if (windowChanged) {
        try {
          await windowManager.setFullScreen(true);
          await windowManager.setAlwaysOnTop(true);
        } catch (_) {}
      }
    }
  }
}

/// Startda (12s dan keyin) va har 15 daqiqada AVTO-yangilanishни tekshiradi.
/// Faqat kiosk band bo'lmaganда (zastavkada yoki murojaat/video yozilmayotganда) o'rnatadi.
class UpdateHost extends ConsumerStatefulWidget {
  const UpdateHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends ConsumerState<UpdateHost> {
  Timer? _t;

  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);

  // Hozir o'rnatsa bo'ladimi? Zastavkada (attract) — ha. Aks holda: hech narsa band
  // emas VA foydalanuvchi bilan muloqot yo'q (1.9.48: avval AI bilan gaplashib turgan
  // odamning suhbati o'rtasida ham o'rnatib, ilovani yopib yuborardi — kioskBusy faqat
  // video/murojaatni sanaydi, ovozli suhbat va ekranga teginishni emas).
  bool _canInstall() {
    try {
      if (ref.read(attractProvider)) return true; // zastavkada — eng xavfsiz payt
      if (ref.read(kioskBusyProvider) != 0) return false; // murojaat/video
      if (ref.read(voiceProvider.notifier).engaged) return false; // ovozli suhbat (≤90s)
      return DateTime.now().difference(_lastTouch).inSeconds >= 120; // ekran 2 daqiqa tinch
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 12), _check);
    _t = Timer.periodic(const Duration(minutes: 15), (_) => _check());
  }

  Future<void> _check() {
    if (!mounted) return Future.value();
    final voice = ref.read(voiceProvider.notifier);
    return UpdateService.check(canInstall: _canInstall, beforeInstall: voice.stop);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _lastTouch = DateTime.now(),
        child: widget.child,
      );
}
