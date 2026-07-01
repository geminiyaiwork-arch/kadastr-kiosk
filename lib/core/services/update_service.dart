import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../env.dart';
import '../../router.dart';

/// Kiosk avto-yangilanish manifesti (portal). Format: {"version":"1.6.1","exe":"https://.../setup.exe","notes":"..."}
const _kUpdateUrl = 'https://andkadastrai.uz/kiosk-latest.json';

/// Windows kioskда avto-yangilanish: manifestni tekshiradi → yangi versiya bo'lsa
/// "Yangi versiya chiqdi" oynasi → "Ha" bosilsa setup.exe yuklab, SOKIN o'rnatib,
/// dastur o'zini yopadi; o'rnatgich yangilab, qayta ishga tushiradi.
class UpdateService {
  static bool _busy = false, _prompting = false;

  static Future<void> check() async {
    if (!Platform.isWindows || _busy || _prompting) return;
    String latest = '', exe = '';
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
      final r = await dio.get(_kUpdateUrl);
      final m = Map<String, dynamic>.from(r.data is Map ? r.data : (r.data is String ? {} : {}));
      latest = (m['version'] ?? '').toString().trim();
      exe = (m['exe'] ?? '').toString().trim();
    } catch (_) {
      return;
    }
    if (latest.isEmpty || exe.isEmpty || !_newer(latest, Env.appVersion)) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _prompting = true;
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Yangi versiya chiqdi', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Kadastr Kiosk $latest versiyasi tayyor. Hozir yangilansinmi?\n\nYangilash bir necha soniya oladi va dastur qayta ochiladi.',
            style: const TextStyle(fontSize: 18, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keyinroq', style: TextStyle(fontSize: 18))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ha, yangilash', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
    _prompting = false;
    if (ok == true) await _install(exe, latest);
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

  static Future<void> _install(String exeUrl, String v) async {
    _busy = true;
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
              Flexible(child: Text('Yangilanmoqda… kuting', style: TextStyle(fontSize: 18))),
            ]),
          ),
        ),
      );
    }
    try {
      final tmp = '${Directory.systemTemp.path}\\kadastr-kiosk-setup-$v.exe';
      await Dio().download(exeUrl, tmp, options: Options(receiveTimeout: const Duration(minutes: 15)));
      // SOKIN o'rnatish: eski nusxa yopiladi, yangilanadi; [Run] qayta ishga tushiradi.
      await Process.start(tmp, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(seconds: 1));
      exit(0); // dastur o'zini yopadi — o'rnatgich davom etadi
    } catch (_) {
      _busy = false;
      final c = rootNavigatorKey.currentContext;
      if (c != null && c.mounted) Navigator.of(c, rootNavigator: true).maybePop();
    }
  }
}

/// Startда (12s dan keyin) va har 30 daqiqada yangilanishни tekshiradi.
class UpdateHost extends StatefulWidget {
  const UpdateHost({super.key, required this.child});
  final Widget child;
  @override
  State<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends State<UpdateHost> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 12), UpdateService.check);
    _t = Timer.periodic(const Duration(minutes: 30), (_) => UpdateService.check());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
