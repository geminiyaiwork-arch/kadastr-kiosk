import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';

/// Documents — name / fee / term list.
class DocsScreen extends ConsumerWidget {
  const DocsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final async = ref.watch(documentsProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pDocs'], sub: t['docSub']),
          AsyncView(async, data: (list) => KCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(T.rCard),
              child: Column(children: [
                Container(
                  color: T.sky,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: Row(children: [
                    Expanded(flex: 2, child: Text(t['pDocs'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: T.navy))),
                    Expanded(child: Text(t['docFee'], textAlign: TextAlign.right, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: T.navy))),
                    Expanded(child: Text(t['docTerm'], textAlign: TextAlign.right, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: T.navy))),
                  ]),
                ),
                for (final d in list)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: T.line))),
                    child: Row(children: [
                      Expanded(flex: 2, child: Text(d.name, style: const TextStyle(fontSize: 22, color: T.ink))),
                      Expanded(child: Text(d.fee, textAlign: TextAlign.right, style: const TextStyle(fontSize: 22, color: T.ink))),
                      Expanded(child: Text(d.term, textAlign: TextAlign.right, style: const TextStyle(fontSize: 22, color: T.ink))),
                    ]),
                  ),
              ]),
            ),
          )),
        ],
      ),
    );
  }
}

/// Reception schedule + booking form (uses the virtual keyboard).
class ReceptionScreen extends ConsumerStatefulWidget {
  const ReceptionScreen({super.key});
  @override
  ConsumerState<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends ConsumerState<ReceptionScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  int? _managerId;
  String? _bookedId;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _book(List<ReceptionManager> mgrs) async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final mid = _managerId ?? (mgrs.isNotEmpty ? mgrs.first.id : null);
    var id = 'Q-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    try {
      final r = await ref.read(dioProvider).post('/reception/book',
          data: {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'managerId': mid});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['id'] != null) id = '${m['id']}';
    } catch (_) {}
    setState(() {
      _bookedId = id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final async = ref.watch(receptionProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pReception'], sub: t['recSub']),
          AsyncView(async, data: (list) {
            if (_bookedId != null) {
              return KCard(
                accent: T.green,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('✓ ${t['recOk']}', style: K.cardH.copyWith(color: T.green)),
                  const SizedBox(height: 12),
                  KvRows([(t['recNum'], _bookedId!)]),
                ]),
              );
            }
            return Column(children: [
              for (final m in list)
                KCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.name, style: K.cardH),
                        if (m.position.isNotEmpty) Text(m.position, style: K.pgSub),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('📅 ${m.days}', style: K.cardP),
                      Text('🕒 ${m.hours}', style: K.cardP),
                    ]),
                  ]),
                ),
              KCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  KField(controller: _name, label: t['recName']),
                  const SizedBox(height: 14),
                  KField(controller: _phone, label: t['recPhone'], hint: '+998'),
                  if (list.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(t['recPickMgr'], style: K.fLabel),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: T.line, width: 2),
                        borderRadius: BorderRadius.circular(T.rInput),
                      ),
                      child: DropdownButton<int>(
                        value: _managerId ?? list.first.id,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        style: K.fInput,
                        items: [for (final m in list) DropdownMenuItem(value: m.id, child: Text('${m.name} — ${m.days} ${m.hours}'))],
                        onChanged: (v) => setState(() => _managerId = v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  KButton(t['recBtn'], onTap: () => _loading ? null : _book(list)),
                ]),
              ),
            ]);
          }),
        ],
      ),
    );
  }
}

/// Xatlov (Law 937) — informational.
class XatlovScreen extends ConsumerWidget {
  const XatlovScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final lang = ref.watch(localeProvider);
    final body = {
      'uz': 'O‘zbekiston Respublikasi Vazirlar Mahkamasining 937-sonli qarori asosida '
          'bino va inshootlar davlat kadastri yuritiladi. Xatlov — ko‘chmas mulk obyektlarini '
          'aniqlash, ro‘yxatga olish va baholash jarayoni. Kerakli ma’lumot uchun tegishli '
          'bo‘lim yoki call-markazga murojaat qiling.',
      'ru': 'На основании постановления Кабинета Министров №937 ведётся государственный '
          'кадастр зданий и сооружений. Опись — процесс выявления, регистрации и оценки '
          'объектов недвижимости. За информацией обратитесь в соответствующий отдел или колл-центр.',
      'en': 'Under Cabinet of Ministers Resolution No. 937, the state cadastre of buildings '
          'and structures is maintained. Inventory is the process of identifying, registering '
          'and valuing real-estate objects. For details, contact the relevant office or call centre.',
    }[lang]!;
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pXatlov']),
          KCard(child: Text(body, style: K.cardP)),
        ],
      ),
    );
  }
}
