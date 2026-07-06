import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../call/call_screen.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';

String _photoUrl(String p) => p.isEmpty ? '' : '${Env.apiBase}$p'; // /api/v1/turniket/photo/...
double _rating(String r) => double.tryParse(r.replaceAll(',', '.')) ?? 0;

/// Telefonlar → XODIMLAR. Grid → bosilса INLINE batafsil profil (canvas ichида, Navigator EMAS)
/// → qo'ng'iroq/video ham INLINE (kiosk 1080×1920 masshtab buzilmaydi).
class PhonesScreen extends ConsumerStatefulWidget {
  const PhonesScreen({super.key});
  @override
  ConsumerState<PhonesScreen> createState() => _PhonesScreenState();
}

class _PhonesScreenState extends ConsumerState<PhonesScreen> {
  Employee? _sel;
  bool _calling = false, _callVideo = false;
  bool _messaging = false, _msgOffline = false, _sending = false, _sentMsg = false;
  final _msgText = TextEditingController();
  final _msgPhone = TextEditingController();

  @override
  void dispose() {
    _msgText.dispose();
    _msgPhone.dispose();
    super.dispose();
  }

  void _startCall(Employee e, bool video) {
    if (!(e.inside || e.online)) {
      // Xodim oflayn — qo'ng'iroq o'rniga xabar qoldirishni taklif qilamiz (ilova/adminга tushadi).
      setState(() { _sel = e; _messaging = true; _msgOffline = true; _sentMsg = false; });
      return;
    }
    setState(() { _sel = e; _callVideo = video; _calling = true; });
  }

  void _openMessage(Employee e) => setState(() { _sel = e; _messaging = true; _msgOffline = false; _sentMsg = false; });

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: T.navy));

  Future<void> _sendMessage() async {
    if (_sending) return;
    if (_msgPhone.text.replaceAll(RegExp(r'\D'), '').length < 7) { _toast('Telefon raqamingizni kiriting — xodim shu raqam orqali bog‘lanadi'); return; }
    if (_msgText.text.trim().isEmpty) { _toast('Xabar matnini yozing'); return; }
    setState(() => _sending = true);
    String? id;
    try {
      final r = await ref.read(dioProvider).post('/appeal', data: {
        'phone': _msgPhone.text.trim(), 'text': _msgText.text.trim(),
        'employee_id': _sel!.id, 'department': _sel!.dept,
        'mode': 'message', 'lang': ref.read(localeProvider),
      });
      id = (Map<String, dynamic>.from(r.data as Map)['id'] ?? '').toString();
    } catch (_) {}
    if (!mounted) return;
    setState(() { _sending = false; if (id != null && id.isNotEmpty) { _sentMsg = true; _msgText.clear(); _msgPhone.clear(); } });
    if (id == null || id.isEmpty) _toast('Yuborilmadi — internetni tekshirib qayta urining');
  }

  @override
  Widget build(BuildContext context) {
    // INLINE qo'ng'iroq — butun canvasни egallaydi (o'z Scaffold'i bor).
    if (_calling && _sel != null) {
      return CallScreen(
        key: ValueKey('call-${_sel!.id}-$_callVideo'),
        employeeId: _sel!.id, name: _sel!.name, video: _callVideo,
        onClose: () { if (mounted) setState(() => _calling = false); },
      );
    }
    final t = ref.watch(trProvider);
    if (_messaging && _sel != null) return KioskScaffold(body: _composer());
    final employees = ref.watch(employeesProvider);
    return KioskScaffold(
      body: _sel == null
          ? _grid(t, employees)
          : _EmployeeDetail(
              employee: _sel!,
              onBack: () => setState(() => _sel = null),
              onCall: (v) => _startCall(_sel!, v),
              onMessage: () => _openMessage(_sel!),
            ),
    );
  }

  Widget _backRow(VoidCallback onTap, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: T.line, width: 1.5), boxShadow: T.shadow),
              child: const Icon(Icons.arrow_back_rounded, color: T.navy, size: 28),
            ),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: T.navy, fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  // Xodimга XABAR — oflayn/onlayn farqi yo'q (xodim ilovasi + admin murojaatlariga tushadi).
  Widget _composer() {
    final e = _sel!;
    if (_sentMsg) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHead('${e.name}', sub: 'Xabar yuborildi'),
        KCard(accent: T.green, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.mark_email_read_rounded, color: T.green, size: 36),
            SizedBox(width: 12),
            Text('Xabaringiz yuborildi', style: TextStyle(color: T.green, fontSize: 24, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          Text('${e.name} xabaringizni ko‘radi va ko‘rsatgan raqamingiz orqali siz bilan bog‘lanadi.',
              style: const TextStyle(color: T.muted, fontSize: 18, height: 1.4)),
          const SizedBox(height: 18),
          KButton('Xodimlar ro‘yxatiga qaytish', onTap: () => setState(() { _messaging = false; _sel = null; })),
        ])),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _backRow(() => setState(() => _messaging = false), _msgOffline ? 'Ortga' : e.name),
      PageHead('${e.name}ga xabar', sub: e.position.isEmpty ? 'Xodimga murojaat' : e.position),
      if (_msgOffline)
        KCard(accent: const Color(0xFFF5A623), child: Row(children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFF5A623), size: 30),
          const SizedBox(width: 14),
          Expanded(child: Text('${e.name} hozir oflayn. Qo‘ng‘iroq o‘rniga xabar qoldiring — xodim ko‘rgach siz bilan bog‘lanadi.',
              style: const TextStyle(color: T.navy, fontSize: 17, height: 1.35))),
        ])),
      KCard(child: Column(children: [
        KField(controller: _msgText, label: 'Xabar matni', hint: 'Xabaringizni yozing…', lines: 4),
        const SizedBox(height: 14),
        KField(controller: _msgPhone, label: 'Telefon raqamingiz *', hint: '+998 __ ___ __ __'),
      ])),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: KButton('Bekor', variant: 'outline', onTap: () => setState(() => _messaging = false))),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: KButton(_sending ? 'Yuborilmoqda…' : 'Xabarni yuborish', onTap: _sendMessage)),
      ]),
    ]);
  }

  Widget _grid(Map<String, dynamic> t, AsyncValue<List<Employee>> employees) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead(t['phEmployees'] ?? 'Xodimlar', sub: t['phSub'] ?? 'Xodim bilan bevosita bog‘laning'),
      employees.when(
        loading: () => const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator(color: T.green))),
        error: (_, __) => _empty(t),
        data: (emps) {
          if (emps.isEmpty) return _empty(t);
          return Column(children: [for (final e in emps) _EmpCard(e, onTap: () => setState(() => _sel = e))]);
        },
      ),
    ]);
  }

  Widget _empty(Map<String, dynamic> t) => KCard(child: Row(children: [
        const Icon(Icons.groups_2_rounded, color: T.muted, size: 40),
        const SizedBox(width: 16),
        Expanded(child: Text(t['phEmpty'] ?? 'Xodimlar hali qo‘shilmagan (admin paneldan qo‘shiladi)',
            style: const TextStyle(color: T.muted, fontSize: 18))),
      ]));
}

// ─────────────────────────── GRID KARTA (premium, to'liq kenglik) ───────────────────────────
class _EmpCard extends StatelessWidget {
  const _EmpCard(this.e, {required this.onTap});
  final Employee e;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final live = e.inside || e.online;
    final photo = _photoUrl(e.photo);
    final rate = _rating(e.rating);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: T.line, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x12102266), blurRadius: 22, offset: Offset(0, 8))],
          ),
          child: Row(children: [
            // Avatar + onlayn nuqta
            Stack(children: [
              Container(
                width: 104, height: 118,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: live ? T.green : T.line, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: photo.isEmpty
                    ? Container(color: T.greenTint, child: const Icon(Icons.person_rounded, color: T.green, size: 54))
                    : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: T.greenTint, child: const Icon(Icons.person_rounded, color: T.green, size: 54))),
              ),
              if (live)
                Positioned(right: 6, bottom: 6, child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(color: T.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                )),
            ]),
            const SizedBox(width: 18),
            // Ma'lumot
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              _statusPill(live),
              const SizedBox(height: 8),
              Text(e.name, style: const TextStyle(color: T.navy, fontSize: 23, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (e.position.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(e.position, style: const TextStyle(color: T.muted, fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (e.dept.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.apartment_rounded, color: T.blue, size: 18),
                  const SizedBox(width: 5),
                  Expanded(child: Text(e.dept, style: const TextStyle(color: T.blue, fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ])),
            const SizedBox(width: 10),
            // O'ng: reyting + chevron
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (rate > 0) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 18),
                  const SizedBox(width: 3),
                  Text(rate.toStringAsFixed(1), style: const TextStyle(color: Color(0xFFB07A12), fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                width: 44, height: 44, alignment: Alignment.center,
                decoration: BoxDecoration(color: T.bg, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right_rounded, color: T.navy, size: 30),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

Widget _statusPill(bool live) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: live ? T.greenTint : const Color(0xFFF0F2F7), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, color: live ? T.green : T.muted, size: 10),
        const SizedBox(width: 6),
        Text(live ? 'Onlayn' : 'Tashqarida', style: TextStyle(color: live ? T.green : T.muted, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    );

// ─────────────────────────── BATAFSIL (premium, INLINE) ───────────────────────────
class _EmployeeDetail extends StatelessWidget {
  const _EmployeeDetail({required this.employee, required this.onBack, required this.onCall, required this.onMessage});
  final Employee employee;
  final VoidCallback onBack;
  final ValueChanged<bool> onCall; // true = video
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final live = e.inside || e.online;
    final photo = _photoUrl(e.photo);
    final rate = _rating(e.rating);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Orqaga
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onTap: onBack,
          behavior: HitTestBehavior.opaque,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: T.line, width: 1.5), boxShadow: T.shadow),
              child: const Icon(Icons.arrow_back_rounded, color: T.navy, size: 28),
            ),
            const SizedBox(width: 14),
            const Text('Xodimlar ro‘yxati', style: TextStyle(color: T.navy, fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      // HERO — gradient profil
      Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(gradient: T.gNavy, borderRadius: BorderRadius.circular(26), boxShadow: T.shadow),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Container(
              width: 168, height: 200,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white24, width: 3)),
              clipBehavior: Clip.antiAlias,
              child: photo.isEmpty
                  ? Container(color: Colors.white10, child: const Icon(Icons.person_rounded, color: Colors.white70, size: 90))
                  : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.white10, child: const Icon(Icons.person_rounded, color: Colors.white70, size: 90))),
            ),
            Positioned(left: 10, bottom: 10, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: live ? T.green : T.muted, size: 10),
                const SizedBox(width: 5),
                Text(live ? 'Onlayn' : 'Tashqarida', style: TextStyle(color: live ? T.green : T.muted, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            )),
          ]),
          const SizedBox(width: 22),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 4),
            Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
            if (e.position.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(e.position, style: const TextStyle(color: Color(0xFFB9C8EE), fontSize: 19, fontWeight: FontWeight.w500)),
            ],
            if (rate > 0) ...[
              const SizedBox(height: 14),
              Row(children: [
                for (int i = 0; i < 5; i++)
                  Icon(i < rate.round() ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFFFC845), size: 24),
                const SizedBox(width: 8),
                Text(rate.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
            ],
          ])),
        ]),
      ),
      const SizedBox(height: 18),
      // AMAL TUGMALARI
      Row(children: [
        if (e.canVoice) _actBtn(Icons.call_rounded, 'Qo‘ng‘iroq', const [T.green, Color(0xFF16A34A)], () => onCall(false)),
        if (e.canVoice && e.canVideo) const SizedBox(width: 14),
        if (e.canVideo) _actBtn(Icons.videocam_rounded, 'Video', const [T.blue, Color(0xFF1E5FD0)], () => onCall(true)),
        const SizedBox(width: 14),
        _actBtn(Icons.chat_bubble_rounded, 'Xabar', const [Color(0xFF7A3FB0), Color(0xFF9B4FD0)], onMessage),
      ]),
      const SizedBox(height: 18),
      // ALOQA MA'LUMOTLARI
      KCard(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Column(children: [
        if (e.dept.isNotEmpty) _infoRow(Icons.apartment_rounded, T.blue, 'Bo‘lim', e.dept),
        if (e.address.isNotEmpty) _infoRow(Icons.location_on_rounded, T.green, 'Manzil', e.address),
        if (e.email.isNotEmpty) _infoRow(Icons.email_rounded, const Color(0xFF7A3FB0), 'Email', e.email),
        if (e.schedule.isNotEmpty) _infoRow(Icons.schedule_rounded, const Color(0xFFF5A623), 'Ish vaqti', e.schedule),
        _infoRow(Icons.badge_rounded, T.navy, 'Lavozim', e.position.isEmpty ? 'Xodim' : e.position, last: true),
      ])),
      // QO'SHIMCHA MA'LUMOTLAR
      if (e.education.isNotEmpty || e.specialization.isNotEmpty || e.experience.isNotEmpty)
        KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(bottom: 14),
              child: Text('Qo‘shimcha ma’lumotlar', style: TextStyle(color: T.navy, fontSize: 22, fontWeight: FontWeight.w800))),
          if (e.education.isNotEmpty) _extraRow(Icons.school_rounded, 'Ma’lumoti', e.education),
          if (e.specialization.isNotEmpty) _extraRow(Icons.workspace_premium_rounded, 'Mutaxassisligi', e.specialization),
          if (e.experience.isNotEmpty) _extraRow(Icons.work_history_rounded, 'Ish tajribasi', e.experience, last: true),
        ])),
    ]);
  }

  Widget _actBtn(IconData ic, String label, List<Color> grad, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: grad.first.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              Icon(ic, color: Colors.white, size: 34),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  Widget _infoRow(IconData ic, Color c, String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: T.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46, height: 46, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(13)),
            child: Icon(ic, color: c, size: 24),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: T.muted, fontSize: 17))),
          Expanded(child: Text(value, style: const TextStyle(color: T.navy, fontSize: 18, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _extraRow(IconData ic, String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: T.line))),
        child: Row(children: [
          Icon(ic, color: T.blue, size: 24),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(color: T.muted, fontSize: 17))),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: T.navy, fontSize: 18, fontWeight: FontWeight.w700))),
        ]),
      );
}
