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

  /// davreestr javobini o'qib label:value ko'rsatadi (struktura moslashuvchan — real
  /// javobni ko'rib keyin aniq maydonlarga moslash mumkin).
  Widget _buildResult(Map<String, dynamic> t, dynamic data) {
    final rows = <(String, String)>[];
    void flatten(dynamic v) {
      if (v is Map) {
        v.forEach((k, val) {
          if (val is Map || val is List) {
            flatten(val);
          } else if (val != null && '$val'.trim().isNotEmpty && '$val' != 'null') {
            rows.add((_pretty('$k'), _clean('$val')));
          }
        });
      } else if (v is List) {
        for (final item in v) {
          flatten(item);
        }
      }
    }

    flatten(data);
    if (rows.isEmpty) {
      return KCard(accent: const Color(0xFFE8A317), child: Text(t['propNotFound'], style: K.cardP));
    }
    return KCard(
      accent: T.green,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t['propResT'], style: K.cardH),
        const SizedBox(height: 12),
        KvRows(rows.take(30).toList()),
        const SizedBox(height: 10),
        Text(t['propReestr'], style: K.pgSub),
      ]),
    );
  }

  String _pretty(String k) {
    final s = k.replaceAll('_', ' ').trim();
    if (s.isEmpty) return k;
    return s[0].toUpperCase() + s.substring(1);
  }

  // HTML teglari kelib qolsa tozalaymiz (davreestr ba'zan matnni teg bilan qaytarishi mumkin)
  String _clean(String v) => v.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

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
                KField(controller: _in, hint: hint),
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
                  Expanded(child: KField(controller: _cap, hint: t['propCapHint'])),
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
