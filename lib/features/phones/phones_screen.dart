import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/i18n/strings.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/widgets.dart';

class PhonesScreen extends ConsumerWidget {
  const PhonesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final employees = ref.watch(employeesProvider);
    final phones = ref.watch(phonesProvider);
    final districts = ref.watch(districtsProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pPhones'], sub: t['phSub']),
          // XODIMLAR — rasm/ism/lavozim + davomat "ichkarida" + qo'ng'iroq
          employees.maybeWhen(
            orElse: () => const SizedBox.shrink(),
            data: (emps) {
              if (emps.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _SectionHead(Icons.groups_rounded, t['phEmployees'] ?? 'Xodimlar bilan bog‘lanish'),
                const SizedBox(height: 12),
                for (final e in emps) _EmployeeCard(e),
                const SizedBox(height: 6),
                _SectionHead(Icons.call_rounded, t['phDirectory'] ?? 'Telefon raqamlar'),
                const SizedBox(height: 12),
              ]);
            },
          ),
          AsyncView(phones, data: (list) {
            final entries = <PhoneEntry>[...list];
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

class _SectionHead extends StatelessWidget {
  const _SectionHead(this.icon, this.title);
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Row(children: [
          Container(
            width: 46, height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(color: T.greenTint, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: T.green, size: 26),
          ),
          const SizedBox(width: 14),
          Text(title, style: const TextStyle(color: T.navy, fontSize: 24, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Xodim kartasi — rasm + ism/lavozim + ichkarida/tashqarida + qo'ng'iroq tugmalari.
class _EmployeeCard extends ConsumerWidget {
  const _EmployeeCard(this.e);
  final Employee e;

  void _call(BuildContext context, bool video) {
    // Phase 2 (WebRTC) + xodim ilovasi ulanganda ishlaydi. Hozircha holat ko'rsatiladi.
    final avail = e.inside || e.online;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(avail
          ? '${e.name} — ${video ? 'video' : 'ovozli'} qo‘ng‘iroq ulanmoqda…'
          : '${e.name} hozir joyida yo‘q — keyinroq urinib ko‘ring'),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final photoUrl = e.photo.isNotEmpty ? '${Env.apiOrigin}${e.photo}' : '';
    final live = e.inside || e.online;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: T.line),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 5))],
      ),
      child: Row(children: [
        // Rasm + holat nuqtasi
        SizedBox(
          width: 74, height: 74,
          child: Stack(children: [
            Container(
              width: 74, height: 74, clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: T.greenTint,
                border: Border.all(color: live ? T.green : T.line, width: 3),
              ),
              child: photoUrl.isNotEmpty
                  ? Image.network(photoUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: T.green, size: 42))
                  : const Icon(Icons.person_rounded, color: T.green, size: 42),
            ),
            Positioned(
              right: 1, bottom: 1,
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: live ? T.green : T.muted,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: T.navy), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (e.position.isNotEmpty)
              Text(e.position, style: K.pgSub, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: (e.inside ? T.green : T.muted).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(
                e.inside ? (t['phInside'] ?? 'Ichkarida') : (e.online ? (t['phOnline'] ?? 'Onlayn') : (t['phOutside'] ?? 'Tashqarida')),
                style: TextStyle(color: e.inside ? T.green : (e.online ? T.blue : T.muted), fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
        // Qo'ng'iroq tugmalari
        if (e.canVoice) _callBtn(Icons.call_rounded, T.green, () => _call(context, false)),
        if (e.canVideo) ...[
          const SizedBox(width: 10),
          _callBtn(Icons.videocam_rounded, T.blue, () => _call(context, true)),
        ],
      ]),
    );
  }

  Widget _callBtn(IconData ic, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 58, height: 58,
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Icon(ic, color: Colors.white, size: 28),
        ),
      );
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
            width: 58, height: 58,
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
