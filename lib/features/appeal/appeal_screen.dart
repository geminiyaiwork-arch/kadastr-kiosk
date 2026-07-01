import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';

/// Murojaat (appeal) yuborish — F.I.Sh + telefon + matn → POST /appeal.
/// Ovozli pult yoki menyudan ochiladi. Mavjud backend /appeal (mode: 'text') ishlatiladi.
class AppealScreen extends ConsumerStatefulWidget {
  const AppealScreen({super.key});
  @override
  ConsumerState<AppealScreen> createState() => _AppealScreenState();
}

class _AppealScreenState extends ConsumerState<AppealScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _text = TextEditingController();
  bool _loading = false;
  bool _err = false;
  String? _sentId;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading) return;
    if (_phone.text.trim().isEmpty || _text.text.trim().isEmpty) {
      setState(() => _err = true);
      return;
    }
    setState(() {
      _loading = true;
      _err = false;
    });
    String? id;
    try {
      final r = await ref.read(dioProvider).post('/appeal', data: {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'text': _text.text.trim(),
        'mode': 'text',
        'lang': ref.read(localeProvider),
      });
      id = (Map<String, dynamic>.from(r.data as Map)['id'] ?? '').toString();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sentId = (id != null && id.isNotEmpty) ? id : '—';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pAppeal'], sub: t['apSub']),
          if (_sentId != null)
            KCard(
              accent: T.green,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('✓ ${t['apOk']}', style: K.cardH.copyWith(color: T.green)),
                const SizedBox(height: 12),
                KvRows([(t['apNum'] as String, _sentId!)]),
                const SizedBox(height: 12),
                Text(t['apThanks'], style: K.cardP),
              ]),
            )
          else
            KCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                KField(controller: _name, label: t['recName']),
                const SizedBox(height: 14),
                KField(controller: _phone, label: t['recPhone'], hint: '+998'),
                const SizedBox(height: 14),
                KField(controller: _text, label: t['apText'], hint: t['apTextHint'], lines: 4),
                if (_err) ...[
                  const SizedBox(height: 10),
                  Text(t['apNeed'], style: K.cardP.copyWith(color: const Color(0xFFD92D2D))),
                ],
                const SizedBox(height: 16),
                KButton(_loading ? '…' : t['apSend'], onTap: _send),
              ]),
            ),
        ],
      ),
    );
  }
}
