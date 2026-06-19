import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/widgets.dart';

class PhonesScreen extends ConsumerWidget {
  const PhonesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final phones = ref.watch(phonesProvider);
    final districts = ref.watch(districtsProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pPhones'], sub: t['phSub']),
          AsyncView(phones, data: (list) {
            final entries = <PhoneEntry>[...list];
            // append district offices with real numbers
            districts.whenData((ds) {
              for (final d in ds) {
                if (d.phoneClean.isNotEmpty) {
                  entries.add(PhoneEntry(name: d.name, dept: t['pDistricts'], number: d.phoneClean));
                }
              }
            });
            if (entries.isEmpty) {
              entries.add(const PhoneEntry(name: 'Call-markaz', dept: 'Davlat kadastrlari palatasi', number: '1148'));
            }
            return Column(children: [for (final p in entries) _PhoneTile(p)]);
          }),
        ],
      ),
    );
  }
}

class _PhoneTile extends StatelessWidget {
  const _PhoneTile(this.p);
  final PhoneEntry p;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: T.line, width: 1.5),
        borderRadius: BorderRadius.circular(T.rCard),
        boxShadow: T.shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: T.greenTint, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: kIcon('phone', size: 32, color: T.green),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: T.ink)),
                if (p.dept.isNotEmpty) Text(p.dept, style: const TextStyle(fontSize: 20, color: T.muted)),
              ],
            ),
          ),
          Text(p.number, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: T.navy)),
        ],
      ),
    );
  }
}
