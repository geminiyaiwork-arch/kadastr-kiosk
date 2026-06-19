import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/text_styles.dart';
import '../core/theme/tokens.dart';
import '../features/common/widgets.dart';

/// Hidden 10-tap zone (top-right corner) → operator menu. Counts taps within 3s.
class OperatorTapZone extends StatefulWidget {
  const OperatorTapZone({super.key});
  @override
  State<OperatorTapZone> createState() => _OperatorTapZoneState();
}

class _OperatorTapZoneState extends State<OperatorTapZone> {
  int _taps = 0;
  DateTime _first = DateTime.fromMillisecondsSinceEpoch(0);

  void _tap() {
    final now = DateTime.now();
    if (now.difference(_first).inSeconds > 3) {
      _taps = 0;
      _first = now;
    }
    _taps++;
    if (_taps >= 10) {
      _taps = 0;
      showOperatorMenu(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _tap,
        child: const SizedBox(width: 110, height: 110),
      ),
    );
  }
}

void showOperatorMenu(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: const Color(0xC7081028),
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Operator', style: K.cardH),
            const SizedBox(height: 20),
            KButton('🔄 Qayta yuklash', variant: 'primary', onTap: () => _confirm(context, 'restart')),
            const SizedBox(height: 12),
            KButton('⏻ O‘chirish', variant: 'navy', onTap: () => _confirm(context, 'shutdown')),
            const SizedBox(height: 12),
            KButton('✕ Ilovadan chiqish', variant: 'outline', onTap: () => exit(0)),
            const SizedBox(height: 12),
            KButton('Bekor', variant: 'outline', onTap: () => Navigator.of(context).pop()),
            const SizedBox(height: 8),
            const Text('Faqat operator uchun', style: TextStyle(fontSize: 17, color: T.muted)),
          ],
        ),
      ),
    ),
  );
}

void _confirm(BuildContext context, String action) {
  final label = action == 'restart' ? 'Qayta yuklash' : 'O‘chirish';
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label?', style: K.cardH),
            const SizedBox(height: 20),
            KButton('Ha, $label', variant: 'navy', onTap: () => _power(action)),
            const SizedBox(height: 12),
            KButton('Bekor', variant: 'outline', onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    ),
  );
}

void _power(String action) {
  try {
    if (Platform.isWindows) {
      Process.run('shutdown', action == 'restart' ? ['/r', '/t', '0'] : ['/s', '/t', '0']);
    } else {
      Process.run('shutdown', action == 'restart' ? ['-r', 'now'] : ['-h', 'now']);
    }
  } catch (_) {}
}
