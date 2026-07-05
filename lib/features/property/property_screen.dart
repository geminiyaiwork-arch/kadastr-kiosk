import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';

/// Ko'chmas mulkni tekshirish — DAVREESTR (davreestr.uz) ochiq ma'lumoti orqali.
/// 2 usul: Kadastr raqami (cad_num) + STIR (org_tin). CAPTCHA majburiy (davreestr himoyasi).
class PropertyScreen extends ConsumerStatefulWidget {
  const PropertyScreen({super.key});
  @override
  ConsumerState<PropertyScreen> createState() => _PropertyScreenState();
}

class _PropertyScreenState extends ConsumerState<PropertyScreen> {
  final _in = TextEditingController();
  final _cap = TextEditingController();
  int _mode = 0; // 0=cad_num (Kadastr) 1=org_tin (STIR)
  bool _loading = false;
  bool _capLoading = false;
  String? _sessionId;
  String? _captchaImg; // data URI (data:image/png;base64,...)
  Widget? _result;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _in.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _capLoading = true;
      _captchaImg = null;
    });
    try {
      final r = await ref.read(dioProvider).get('/parcel/reestr/captcha');
      final m = Map<String, dynamic>.from(r.data as Map);
      setState(() {
        _sessionId = '${m['session_id'] ?? ''}';
        _captchaImg = '${m['captcha'] ?? ''}';
      });
    } catch (_) {
      setState(() {
        _sessionId = null;
        _captchaImg = null;
      });
    } finally {
      if (mounted) setState(() => _capLoading = false);
    }
  }

  Future<void> _check(Map<String, dynamic> t) async {
    final num = _in.text.trim();
    final cap = _cap.text.trim();
    if (num.isEmpty) return;
    if (cap.isEmpty || _sessionId == null) {
      setState(() => _result = KCard(accent: T.recRed, child: Text(t['propCapHint'], style: K.cardP)));
      if (_sessionId == null) _loadCaptcha();
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(dioProvider).post('/parcel/reestr/search', data: {
        'session_id': _sessionId,
        'type': _mode == 0 ? 'cad_num' : 'org_tin',
        'number': num,
        'captcha': cap,
      });
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['ok'] == true) {
        setState(() => _result = _buildResult(t, m['data']));
      } else {
        final capErr = m['captcha_error'] == true;
        setState(() => _result = KCard(
              accent: T.recRed,
              child: Text(capErr ? t['propCapErr'] : '${m['message'] ?? t['propNotFound']}', style: K.cardP),
            ));
      }
    } catch (_) {
      setState(() => _result = KCard(accent: T.recRed, child: Text(t['propNotFound'], style: K.cardP)));
    } finally {
      // CAPTCHA bir martalik — har so'rovdan keyin yangisini olamiz
      _cap.clear();
      _loadCaptcha();
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _fieldIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('turi') || l.contains("ob'ekt") || l.contains('obekt')) return Icons.apartment_rounded;
    if (l.contains('maydon')) return Icons.crop_free_rounded;
    if (l.contains('mulkdor')) return Icons.groups_rounded;
    if (l.contains('qiymat') || l.contains('narx')) return Icons.savings_outlined;
    if (l.contains('sana') || l.contains('kun')) return Icons.calendar_month_rounded;
    if (l.contains('chirma') || l.contains('raqam') || l.contains('nomer')) return Icons.qr_code_2_rounded;
    return Icons.info_outline_rounded;
  }

  /// davreestr natijasi: {title (kadastr raqami), location (manzil), fields:[{label,value}]}.
  /// Dizayn: yashil chap-chegara, NATIJA sarlavha, ikonkali qatorlar, qiymatlar O'NGGA tekislangan.
  Widget _buildResult(Map<String, dynamic> t, dynamic data) {
    final m = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final title = '${m['title'] ?? ''}'.trim();
    final location = '${m['location'] ?? ''}'.trim();
    final rows = <(String, String)>[];
    for (final f in (m['fields'] as List? ?? const [])) {
      if (f is Map) {
        final l = '${f['label'] ?? ''}'.trim();
        final v = '${f['value'] ?? ''}'.trim();
        if (l.isNotEmpty && v.isNotEmpty) rows.add((l, v));
      }
    }
    if (title.isEmpty && rows.isEmpty) {
      return KCard(accent: const Color(0xFFE8A317), child: Text(t['propNotFound'], style: K.cardP));
    }
    Widget fieldRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(_fieldIcon(label), color: T.green, size: 28),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: Text(label, style: const TextStyle(color: T.navy, fontSize: 19, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: T.navy, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ]),
        );

    return Container(
      margin: const EdgeInsets.only(top: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: T.line, width: 1),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 26, offset: Offset(0, 10))],
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 8, color: T.green), // yashil chap chegara
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Sarlavha: NATIJA + kadastr raqami
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.fact_check_rounded, color: T.green, size: 42),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t['propResT'].toString().toUpperCase(),
                          style: const TextStyle(color: T.green, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      if (title.isNotEmpty)
                        Text(title,
                            style: const TextStyle(color: T.blue, fontSize: 36, fontWeight: FontWeight.w800, height: 1.05)),
                    ]),
                  ),
                ]),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_rounded, color: T.blue, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(location, style: const TextStyle(color: T.blue, fontSize: 19, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
                const SizedBox(height: 14),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Container(height: 1, color: T.line),
                  fieldRow(rows[i].$1, rows[i].$2),
                ],
                const SizedBox(height: 14),
                // Pastki banner: manba
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(color: T.greenTint, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.verified_user_rounded, color: T.green, size: 24),
                    const SizedBox(width: 12),
                    Expanded(child: _reestrNote(t)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // "Ma'lumot davreestr.uz Davlat reestridan olinadi" — davreestr.uz ko'k rangда
  Widget _reestrNote(Map<String, dynamic> t) {
    final full = '${t['propReestr']}';
    const link = 'davreestr.uz';
    final i = full.indexOf(link);
    const base = TextStyle(color: T.navy, fontSize: 16, fontWeight: FontWeight.w500);
    if (i < 0) return Text(full, style: base);
    return Text.rich(TextSpan(style: base, children: [
      TextSpan(text: full.substring(0, i)),
      const TextSpan(text: link, style: TextStyle(color: T.blue, fontWeight: FontWeight.w700)),
      TextSpan(text: full.substring(i + link.length)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final modes = (t['propModes'] as List).cast<String>();
    final hint = _mode == 0 ? t['propPh'] : (t['propPhStir'] ?? t['propPh']);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead((t['svc'] as List)[0], sub: t['propSub']),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  for (var i = 0; i < modes.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _mode = i;
                          _result = null;
                          _in.clear();
                        }),
                        child: Container(
                          margin: EdgeInsets.only(right: i < modes.length - 1 ? 10 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _mode == i ? T.sky : Colors.white,
                            border: Border.all(color: _mode == i ? T.blue : T.line, width: 2),
                            borderRadius: BorderRadius.circular(T.rInput),
                          ),
                          child: Text(modes[i],
                              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: _mode == i ? T.blue : T.muted)),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                KField(controller: _in, hint: hint, onEnter: () => _check(t)),
                const SizedBox(height: 16),
                // CAPTCHA — rasm + yangilash + kiritish (davreestr himoyasi)
                Row(children: [
                  Container(
                    width: 190,
                    height: 66,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: T.line, width: 2),
                      borderRadius: BorderRadius.circular(T.rInput),
                    ),
                    child: _capLoading
                        ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : (_captchaImg != null && _captchaImg!.contains('base64,')
                            ? Image.memory(base64Decode(_captchaImg!.split('base64,')[1]), fit: BoxFit.contain, gaplessPlayback: true)
                            : const Icon(Icons.image_not_supported_outlined, size: 30)),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _capLoading ? null : _loadCaptcha,
                    child: Container(
                      width: 66,
                      height: 66,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: T.sky,
                        border: Border.all(color: T.blue, width: 2),
                        borderRadius: BorderRadius.circular(T.rInput),
                      ),
                      child: Icon(Icons.refresh_rounded, color: T.blue, size: 32),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: KField(controller: _cap, hint: t['propCapHint'], onEnter: () => _check(t))),
                ]),
                const SizedBox(height: 16),
                KButton(_loading ? '…' : t['propBtn'], onTap: () => _loading ? null : _check(t)),
              ],
            ),
          ),
          if (_result != null) _result!,
          const SizedBox(height: 10),
          Center(child: Text(t['propReestr'], textAlign: TextAlign.center, style: K.pgSub)),
        ],
      ),
    );
  }
}
