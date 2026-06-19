import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';

/// Temporary page chrome for screens built in later milestones (M2+).
class KioskPlaceholder extends ConsumerWidget {
  const KioskPlaceholder({super.key, required this.titleKey, this.milestone = 'M2'});
  final String titleKey;
  final String milestone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t[titleKey] ?? titleKey),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: T.line, width: 1.5),
              borderRadius: BorderRadius.circular(T.rCard),
              boxShadow: T.shadow,
            ),
            child: Text('$milestone — tez orada', style: K.cardP),
          ),
        ],
      ),
    );
  }
}
