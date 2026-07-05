import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/util/fmt.dart';
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
  bool _bookFail = false; // tarmoq/server xatosi — soxta "yozildingiz" ko'rsatmaslik uchun

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _book(List<ReceptionManager> mgrs) async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _bookFail = false;
    });
    final mid = _managerId ?? (mgrs.isNotEmpty ? mgrs.first.id : null);
    String? id;
    try {
      final r = await ref.read(dioProvider).post('/reception/book',
          data: {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'managerId': mid});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['id'] != null) id = '${m['id']}';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      // MUVAFFAQIYAT FAQAT server haqiqiy id qaytarganda — soxta lokal Q-raqam YO'Q.
      if (id != null && id.isNotEmpty) {
        _bookedId = id;
      } else {
        _bookFail = true;
      }
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
                  if (_bookFail) ...[
                    const SizedBox(height: 10),
                    Text(t['recFail'], style: K.cardP.copyWith(color: const Color(0xFFD92D2D))),
                  ],
                  const SizedBox(height: 16),
                  KButton(_loading ? '…' : t['recBtn'], onTap: () => _loading ? null : _book(list)),
                ]),
              ),
            ]);
          }),
        ],
      ),
    );
  }
}

/// Xatlov (937) — Andijon: tumanlar kesimi → tuman ustiga bosilsa PADROBNI (barcha ustunlar).
class XatlovScreen extends ConsumerStatefulWidget {
  const XatlovScreen({super.key});
  @override
  ConsumerState<XatlovScreen> createState() => _XatlovScreenState();
}

class _XatlovScreenState extends ConsumerState<XatlovScreen> {
  String? _sel; // tanlangan tuman kodi (null = tumanlar ro'yxati)

  String? _findKey(List cols, List<String> needles) {
    for (final c in cols) {
      final s = '${c['group'] ?? ''} ${c['label'] ?? ''}'.toLowerCase();
      if (needles.every((n) => s.contains(n))) return c['key'] as String?;
    }
    return null;
  }

  String _val(Map v, String? key) {
    if (key == null) return '—';
    final x = v[key];
    if (x == null) return '—';
    final n = num.tryParse('$x');
    return n != null ? fmt(n) : '$x';
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final async = ref.watch(xatlov937Provider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pXatlov'], sub: _sel == null ? 'Andijon viloyati — tumanlar kesimida' : 'Andijon viloyati'),
          AsyncView(async, data: (d) {
            final cols = (d['columns'] as List?) ?? const [];
            final dist = (d['districts'] as List?) ?? const [];
            if (dist.isEmpty) return _info();
            final mfyK = _findKey(cols, ['мфй', 'сони']);
            final objK = _findKey(cols, ['маҳалладаги']);
            final xatK = _findKey(cols, ['хатлов ўтказилган']);
            if (_sel != null) {
              for (final raw in dist) {
                final x = Map<String, dynamic>.from(raw as Map);
                if ('${x['code']}' == _sel) return _detail(x, cols);
              }
              _sel = null;
            }
            return _listView(Map<String, dynamic>.from(d as Map), dist, mfyK, objK, xatK);
          }),
        ],
      ),
    );
  }

  Widget _listView(Map<String, dynamic> d, List dist, String? mfyK, String? objK, String? xatK) {
    final total = Map<String, dynamic>.from((d['total'] as Map?) ?? const {});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Viloyat JAMI — yashil chegarali karta + KPI plitkalar
      _bordered(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.fact_check_rounded, color: T.green, size: 40),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('937-QONUN — XATLOV', style: TextStyle(color: T.green, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
            Text('${d['region'] ?? 'Andijon viloyati'} — jami', style: const TextStyle(color: T.navy, fontSize: 26, fontWeight: FontWeight.w800)),
            if ('${d['asOf'] ?? ''}'.isNotEmpty) Text('Sana: ${d['asOf']}', style: K.pgSub),
          ])),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _kpiTile(Icons.holiday_village_rounded, 'MFY', _val(total, mfyK), T.green),
          _kpiTile(Icons.apartment_rounded, 'Obyektlar', _val(total, objK), T.blue),
          _kpiTile(Icons.checklist_rtl_rounded, 'Xatlov', _val(total, xatK), T.green),
        ]),
      ])),
      const SizedBox(height: 8),
      for (final raw in dist)
        Builder(builder: (_) {
          final x = Map<String, dynamic>.from(raw as Map);
          final v = Map<String, dynamic>.from((x['values'] as Map?) ?? const {});
          return _districtTile('${x['name']}', _val(v, mfyK), _val(v, objK), _val(v, xatK), () => setState(() => _sel = '${x['code']}'));
        }),
    ]);
  }

  // Yashil (yoki ko'k) chap-chegarali oq karta — Ko'chmas mulk natijasi uslubida.
  Widget _bordered({required Widget child, Color accent = T.green}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: T.line),
          boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 7, color: accent),
            Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(22, 20, 22, 20), child: child)),
          ]),
        ),
      );

  Widget _kpiTile(IconData ic, String label, String value, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, color: color, size: 26),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: T.navy, fontSize: 30, fontWeight: FontWeight.w800)),
            Text(label, style: K.pgSub),
          ]),
        ),
      );

  Widget _districtTile(String name, String mfy, String obj, String xat, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: T.line),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 5))],
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(color: T.greenTint, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.location_city_rounded, color: T.green, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(name, style: const TextStyle(color: T.navy, fontSize: 21, fontWeight: FontWeight.w700))),
            _stat('MFY', mfy),
            _stat('Obyekt', obj),
            _stat('Xatlov', xat),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 40, color: T.muted),
          ]),
        ),
      );

  Widget _stat(String l, String v) => Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(v, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: T.navy)),
          Text(l, style: const TextStyle(fontSize: 14, color: T.muted)),
        ]),
      );

  Widget _detail(Map<String, dynamic> dd, List cols) {
    final v = Map<String, dynamic>.from((dd['values'] as Map?) ?? const {});
    final groups = <String, List<Map>>{};
    final order = <String>[];
    for (final raw in cols) {
      final c = Map<String, dynamic>.from(raw as Map);
      final g = '${c['group'] ?? ''}';
      groups.putIfAbsent(g, () { order.add(g); return <Map>[]; }).add(c);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _sel = null),
          child: Container(
            width: 68, height: 68, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: T.line, width: 1.5), borderRadius: BorderRadius.circular(16), boxShadow: T.shadow),
            child: const Icon(Icons.chevron_left_rounded, size: 42, color: T.navy),
          ),
        ),
        const SizedBox(width: 16),
        const Icon(Icons.location_city_rounded, color: T.green, size: 34),
        const SizedBox(width: 10),
        Expanded(child: Text('${dd['name']}', style: K.pgTitle)),
      ])),
      for (final g in order) ...[
        Padding(padding: const EdgeInsets.fromLTRB(6, 12, 6, 8), child: Text(g, style: const TextStyle(color: T.blue, fontSize: 20, fontWeight: FontWeight.w800))),
        _bordered(accent: T.blue, child: Column(children: [
          for (var i = 0; i < groups[g]!.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(border: i == groups[g]!.length - 1 ? null : const Border(bottom: BorderSide(color: T.line))),
              child: Row(children: [
                Expanded(flex: 5, child: Text('${groups[g]![i]['label']}', style: const TextStyle(color: T.navy, fontSize: 18, fontWeight: FontWeight.w500))),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: Text(_val(v, groups[g]![i]['key'] as String?), textAlign: TextAlign.right, style: const TextStyle(color: T.navy, fontSize: 21, fontWeight: FontWeight.w800))),
              ]),
            ),
        ])),
      ],
    ]);
  }

  Widget _info() {
    final lang = ref.watch(localeProvider);
    final body = {
      'uz': 'O‘zbekiston Respublikasi Vazirlar Mahkamasining 937-sonli qarori asosida bino va inshootlar davlat '
          'kadastri yuritiladi. Bu yerda Andijon viloyati bo‘yicha xatlov ma’lumotlari ko‘rsatiladi (hozircha yuklanmagan).',
      'ru': 'На основании постановления №937 ведётся государственный кадастр зданий и сооружений. Здесь '
          'отображаются данные описи по Андижанской области (пока не загружены).',
      'en': 'Under Resolution No. 937, the state cadastre of buildings is maintained. Andijan region inventory '
          'data appears here (not uploaded yet).',
    }[lang]!;
    return KCard(child: Text(body, style: K.cardP));
  }
}
