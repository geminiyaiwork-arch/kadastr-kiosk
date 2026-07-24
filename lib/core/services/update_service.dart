import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../env.dart';
import '../../router.dart';

/// Kiosk avto-yangilanish manifesti (portal). Format: {"version":"1.6.1","exe":"https://.../setup.exe","notes":"..."}
const _kUpdateUrl = 'https://andkadastrai.uz/kiosk-latest.json';

/// Kiosk AVTO-yangilanish: nazoratsiz qurilma bo'lgani uchun HECH KIMDAN SO'RAMASDAN
/// o'zini yangilaydi. Yangi versiya topilsa (manifest version > Env.appVersion), band
/// bo'lmagan (video/murojaat yozilmayotgan / zastavkada) paytда jim yuklab, sokin o'rnatib,
/// dastur o'zini qayta ochadi. Band bo'lsa — o'rnatmaydi, keyingi tekshiruvда qayta urinadi.
class UpdateService {
  static bool _busy = false;

  /// [canInstall] — hozir o'rnatsa bo'ladimi (faol foydalanuvchini uzmaslik uchun).
  /// null yoki true qaytarsa darhol o'rnatadi; false qaytarsa — bu safar o'tkazadi.
  static Future<void> check({bool Function()? canInstall}) async {
    if ((!Platform.isWindows && !Platform.isLinux) || _busy) return;
    String latest = '', exe = '', deb = '';
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
      final r = await dio.get(_kUpdateUrl);
      final m = Map<String, dynamic>.from(r.data is Map ? r.data : (r.data is String ? {} : {}));
      latest = (m['version'] ?? '').toString().trim();
      exe = (m['exe'] ?? '').toString().trim();
      deb = (m['deb'] ?? '').toString().trim();
    } catch (_) {
      return;
    }
    final pkgUrl = Platform.isWindows ? exe : deb;
    if (latest.isEmpty || pkgUrl.isEmpty || !_newer(latest, Env.appVersion)) return;
    // Faol foydalanuvchini uzmaslik: band bo'lsa (murojaat/video) hozir o'rnatmaymiz —
    // keyingi (15 daqiqalik) tekshiruv yoki zastavkaga o'tganda o'rnatadi.
    if (canInstall != null && !canInstall()) return;
    await _install(pkgUrl, latest);
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

  static Future<void> _install(String pkgUrl, String v) async {
    _busy = true;
    // So'ramaymiz, lekin ekranда qisqa "Yangilanmoqda…" ko'rsatamiz (fuqaro tushunsin).
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
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
    try {
      if (Platform.isWindows) {
        final tmp = '${Directory.systemTemp.path}\\kadastr-kiosk-setup-$v.exe';
        await Dio().download(pkgUrl, tmp, options: Options(receiveTimeout: const Duration(minutes: 15)));
        // MUHIM: UAC (ruxsat) oynasi TO'LIQ-EKRAN kiosk ORQASIDA qolib, yangilanish
        // hech qachon boshlanmasdi! O'rnatishdan oldin kiosk kichrayadi — UAC ko'rinadi.
        try {
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          await windowManager.minimize();
        } catch (_) {}
        // /SILENT: kichik jarayon-oynasi ko'rinadi; [Run] postinstall kioskни QAYTA ochadi.
        await Process.start(tmp, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
            mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 1));
        exit(0); // dastur o'zini yopadi — o'rnatgich davom etadi
      } else {
        // LINUX: deb'ни yuklab, pkexec (grafik parol-oyna) bilan o'rnatamiz,
        // so'ng yangi versiyani ishga tushirib, o'zimizni yopamiz.
        final tmp = '${Directory.systemTemp.path}/kadastr-kiosk-$v.deb';
        await Dio().download(pkgUrl, tmp, options: Options(receiveTimeout: const Duration(minutes: 15)));
        try {
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setFullScreen(false);
          await windowManager.minimize();
        } catch (_) {}
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
      if (c != null && c.mounted) Navigator.of(c, rootNavigator: true).maybePop();
      try {
        await windowManager.setFullScreen(true);
        await windowManager.setAlwaysOnTop(true);
      } catch (_) {}
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

  // Hozir o'rnatsa bo'ladimi? Zastavkada (attract) yoki hech narsa bilan band emas bo'lsa — ha.
  bool _canInstall() {
    try {
      if (ref.read(attractProvider)) return true;      // zastavkada — eng xavfsiz payt
      return ref.read(kioskBusyProvider) == 0;          // murojaat/video yozilmayotgan bo'lsa
    } catch (_) {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 12), () => UpdateService.check(canInstall: _canInstall));
    _t = Timer.periodic(const Duration(minutes: 15), (_) => UpdateService.check(canInstall: _canInstall));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
