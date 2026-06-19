import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/strings.dart';
import '../core/theme/press.dart';
import '../core/theme/tokens.dart';

const _opts = [
  ('uz', '🇺🇿 O‘zbekcha'),
  ('ru', '🇷🇺 Русский'),
  ('en', '🇬🇧 English'),
];

void showLangModal(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierLabel: 'lang',
    barrierDismissible: true,
    barrierColor: const Color(0x990C1430),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (_, anim, __, ___) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Opacity(opacity: anim.value, child: const Center(child: _LangModal())),
    ),
  );
}

class _LangModal extends ConsumerWidget {
  const _LangModal();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(44),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(T.rModal)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t['chooseLang'], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: T.navy)),
            const SizedBox(height: 24),
            for (var i = 0; i < _opts.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: Press(
                  onTap: () {
                    ref.read(localeProvider.notifier).state = _opts[i].$1;
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: T.line, width: 2),
                      borderRadius: BorderRadius.circular(T.rCard),
                    ),
                    child: Text(_opts[i].$2, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: T.ink)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
