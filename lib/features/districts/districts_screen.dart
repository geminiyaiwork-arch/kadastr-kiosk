import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/press.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/fmt.dart';
import '../../shell/kiosk_shell.dart';
import '../common/widgets.dart';

class DistrictsScreen extends ConsumerWidget {
  const DistrictsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final async = ref.watch(districtsProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pDistricts'], sub: t['distSub']),
          AsyncView(async, data: (list) => GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 4.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final d in list) _DistTile(d: d, objects: t['objects']),
            ],
          )),
        ],
      ),
    );
  }
}

class _DistTile extends StatelessWidget {
  const _DistTile({required this.d, required this.objects});
  final District d;
  final String objects;
  @override
  Widget build(BuildContext context) {
    return Press(
      onTap: () => context.go('/district/${Uri.encodeComponent(d.name)}'),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: T.line, width: 1.5),
          borderRadius: BorderRadius.circular(T.rCard),
          boxShadow: T.shadow,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: T.sky, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: kIcon('pin', size: 30, color: T.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(d.name, style: K.distName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${fmt(d.auksion)} $objects', style: K.distCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DistrictDetailScreen extends ConsumerWidget {
  const DistrictDetailScreen({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final async = ref.watch(districtsProvider);
    final labels = (t['distKV'] as List).cast<String>();
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(name, sub: t['pDistricts']),
          AsyncView(async, data: (list) {
            final d = list.firstWhere((x) => x.name == name,
                orElse: () => District.fromJson({'name': name}));
            final rows = <(String, String)>[
              (labels[0], d.head),
              (labels[1], d.engineer),
              (labels[2], d.phoneClean.isEmpty ? '—' : d.phoneClean),
              (labels[3], d.hours),
              (labels[4], '${fmt(d.auksion)} ${t['objects']}'),
              (labels[5], '${fmt(d.arizalar)} ${t['applications']}'),
            ];
            return KCard(accent: T.green, child: KvRows(rows));
          }),
        ],
      ),
    );
  }
}
