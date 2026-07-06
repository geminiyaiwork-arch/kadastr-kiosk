import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/i18n/strings.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../call/call_screen.dart';
import '../common/widgets.dart';

String _photoUrl(String p) => p.isEmpty ? '' : '${Env.apiBase}$p'; // /api/v1/turniket/photo/...

/// Telefonlar → XODIMLAR direktoriyasi (grid). Bosilса — batafsil profil + qo'ng'iroq.
class PhonesScreen extends ConsumerWidget {
  const PhonesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final employees = ref.watch(employeesProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['phEmployees'] ?? 'Xodimlar', sub: t['phSub']),
          employees.when(
            loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: T.green))),
            error: (_, __) => const SizedBox.shrink(),
            data: (emps) {
              if (emps.isEmpty) {
                return KCard(child: Text(t['phEmpty'] ?? 'Xodimlar hali qo‘shilmagan (admin panelдан qo‘shiladi)', style: K.cardP));
              }
              return GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.55,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [for (final e in emps) _EmpCard(e)],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmpCard extends StatelessWidget {
  const _EmpCard(this.e);
  final Employee e;
  @override
  Widget build(BuildContext context) {
    final live = e.inside || e.online;
    final photo = _photoUrl(e.photo);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmployeeDetailScreen(employee: e))),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: T.line),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 5))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 78, height: 92, color: T.greenTint,
              child: photo.isNotEmpty
                  ? Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: T.green, size: 44))
                  : const Icon(Icons.person_rounded, color: T.green, size: 44),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Icon(Icons.circle, color: live ? T.green : T.muted, size: 11),
                const SizedBox(width: 6),
                Text(live ? (e.inside ? 'Onlayn' : 'Onlayn') : 'Tashqarida',
                    style: TextStyle(color: live ? T.green : T.muted, fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text(e.name, style: const TextStyle(color: T.navy, fontSize: 19, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (e.position.isNotEmpty)
                Text(e.position, style: const TextStyle(color: T.muted, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (e.dept.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.location_on_rounded, color: T.blue, size: 15),
                  const SizedBox(width: 3),
                  Expanded(child: Text(e.dept, style: const TextStyle(color: T.blue, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: T.muted, size: 30),
        ]),
      ),
    );
  }
}

// ─────────────────────────── BATAFSIL (mockup 2) ───────────────────────────
class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.employee});
  final Employee employee;

  void _call(BuildContext context, bool video) {
    if (!(employee.inside || employee.online)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${employee.name} hozir joyida yo‘q')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(employeeId: employee.id, name: employee.name, video: video)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final e = employee;
    final live = e.inside || e.online;
    final photo = _photoUrl(e.photo);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(e.name, sub: t['phEmployees'] ?? 'Xodimlar'),
          // Profil karta
          KCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(
                width: 260, height: 320, color: T.greenTint,
                child: photo.isNotEmpty
                    ? Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: T.green, size: 120))
                    : const Icon(Icons.person_rounded, color: T.green, size: 120),
              )),
              Positioned(left: 12, bottom: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: T.shadow),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, color: live ? T.green : T.muted, size: 11),
                  const SizedBox(width: 6),
                  Text(live ? 'Onlayn' : 'Tashqarida', style: TextStyle(color: live ? T.green : T.muted, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
              )),
            ]),
            const SizedBox(width: 24),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: const TextStyle(color: T.navy, fontSize: 30, fontWeight: FontWeight.w800)),
              if (e.position.isNotEmpty) Text(e.position, style: const TextStyle(color: T.muted, fontSize: 19)),
              const SizedBox(height: 16),
              if (e.dept.isNotEmpty) _row(Icons.work_rounded, 'Bo‘lim', e.dept),
              if (e.address.isNotEmpty) _row(Icons.location_on_rounded, 'Manzil', e.address),
              if (e.email.isNotEmpty) _row(Icons.email_rounded, 'Email', e.email),
              if (e.schedule.isNotEmpty) _row(Icons.event_rounded, 'Ish vaqti', e.schedule),
              if (e.position.isNotEmpty) _row(Icons.badge_rounded, 'Lavozim', e.position, last: true),
            ])),
          ])),
          const SizedBox(height: 14),
          // Amal tugmalari
          KCard(child: Row(children: [
            if (e.canVoice) _act(Icons.call_rounded, t['phCall'] ?? 'Qo‘ng‘iroq qilish', T.green, () => _call(context, false)),
            if (e.canVideo) _act(Icons.videocam_rounded, t['phVideo'] ?? 'Video qo‘ng‘iroq', T.blue, () => _call(context, true)),
            _act(Icons.chat_bubble_rounded, t['phMsg'] ?? 'Xabar yozish', T.blue, () =>
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['phSoon'] ?? 'Tez kunda')))),
            _act(Icons.ios_share_rounded, t['phMore'] ?? 'Boshqa', T.blue, () =>
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['phSoon'] ?? 'Tez kunda')))),
          ])),
          const SizedBox(height: 14),
          // Qo'shimcha ma'lumotlar
          if (e.education.isNotEmpty || e.specialization.isNotEmpty || e.experience.isNotEmpty || e.rating.isNotEmpty)
            KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t['phExtra'] ?? 'Qo‘shimcha ma’lumotlar', style: const TextStyle(color: T.navy, fontSize: 22, fontWeight: FontWeight.w800))),
              if (e.education.isNotEmpty) _erow(Icons.menu_book_rounded, 'Ma’lumot', e.education),
              if (e.specialization.isNotEmpty) _erow(Icons.account_balance_rounded, 'Mutaxassisligi', e.specialization),
              if (e.experience.isNotEmpty) _erow(Icons.work_history_rounded, 'Ish tajribasi', e.experience),
              if (e.rating.isNotEmpty) _erow(Icons.star_rounded, 'Baholash', '${e.rating} / 5 ⭐', last: true),
            ])),
        ],
      ),
    );
  }

  Widget _row(IconData ic, String label, String value, {bool last = false}) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, color: T.blue, size: 22),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: T.muted, fontSize: 17)),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: T.navy, fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _act(IconData ic, String label, Color color, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            Icon(ic, color: color, size: 42),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: T.navy, fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _erow(IconData ic, String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: T.line))),
        child: Row(children: [
          Icon(ic, color: T.blue, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: T.muted, fontSize: 17))),
          Text(value, style: const TextStyle(color: T.navy, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );
}

