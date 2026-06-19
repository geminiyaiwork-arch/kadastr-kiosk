import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';

class PropertyScreen extends ConsumerStatefulWidget {
  const PropertyScreen({super.key});
  @override
  ConsumerState<PropertyScreen> createState() => _PropertyScreenState();
}

class _PropertyScreenState extends ConsumerState<PropertyScreen> {
  final _in = TextEditingController();
  int _mode = 0; // 0=kadastr 1=jshshir 2=passport
  bool _loading = false;
  Widget? _result;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _check(Map<String, dynamic> t) async {
    final num = _in.text.trim();
    if (num.isEmpty) return;
    if (_mode != 0) {
      setState(() => _result = KCard(accent: const Color(0xFFE8A317), child: Text(t['propSoon'], style: K.cardP)));
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(dioProvider).get('/parcel/check', queryParameters: {'kadastr': num});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['found'] == true) {
        final kv = (t['propKV'] as List).cast<String>();
        setState(() => _result = KCard(
              accent: T.green,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t['propResT'], style: K.cardH),
                const SizedBox(height: 12),
                KvRows([
                  (kv[0], '${m['obyekt'] ?? ''}'),
                  (kv[1], '${m['manzil'] ?? ''}'),
                  (kv[2], '${m['maydon'] ?? ''}'),
                  (kv[3], '${m['kadastr'] ?? ''}'),
                  (kv[4], '${m['holat'] ?? ''}'),
                ]),
              ]),
            ));
      } else {
        setState(() => _result = KCard(accent: T.recRed, child: Text(t['propNotFound'], style: K.cardP)));
      }
    } catch (_) {
      setState(() => _result = KCard(accent: T.recRed, child: Text(t['propNotFound'], style: K.cardP)));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final modes = (t['propModes'] as List).cast<String>();
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead((t['svc'] as List)[0], sub: t['propSub']),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                  ],
                ),
                const SizedBox(height: 16),
                KField(controller: _in, hint: t['propPh'], onEnter: () => _check(t)),
                const SizedBox(height: 16),
                KButton(t['propBtn'], onTap: () => _loading ? null : _check(t)),
              ],
            ),
          ),
          if (_result != null) _result!,
          const SizedBox(height: 10),
          Center(child: Text(t['demo'], textAlign: TextAlign.center, style: K.pgSub)),
        ],
      ),
    );
  }
}
