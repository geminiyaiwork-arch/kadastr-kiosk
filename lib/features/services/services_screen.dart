import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../shell/kiosk_shell.dart';
import '../common/svc_tile.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final svc = t['svc'] as List;
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['navServices']),
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 22,
            crossAxisSpacing: 22,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < svcList.length; i++)
                SvcTile(
                  icon: svcList[i].$2,
                  label: svc[i],
                  variant: svcList[i].$3,
                  onTap: () => context.go('/${svcList[i].$1}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
