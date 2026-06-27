import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/env.dart';
import '../../core/i18n/strings.dart';
import '../../core/network/models.dart';
import '../../core/network/repository.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/press.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/fmt.dart';
import '../../shell/kiosk_shell.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';
import 'face_capture.dart';
import 'ill_i18n.dart';

class IllegalScreen extends ConsumerStatefulWidget {
  const IllegalScreen({super.key});
  @override
  ConsumerState<IllegalScreen> createState() => _IllegalScreenState();
}

class _IllegalScreenState extends ConsumerState<IllegalScreen> {
  final _jshshir = TextEditingController();
  final _birth = TextEditingController();
  final _pass = TextEditingController();
  String? _method; // jshshir | passport | qr
  String? _error;
  bool _loading = false;
  bool _searched = false;
  List<IllegalRecord> _records = const [];
  String? _qrUrl;
  String? _qrError;
  bool _qrPolling = false;
  bool _faceMode = false; // JSHSHIR/Pasport: in-page native camera (Face-ID) step
  String? _verifyError; // MyID error (shown to user / for support)
  Map<String, dynamic>? _profile; // MyID verified profile
  int? _vCode; // MyID result_code (1 = muvaffaqiyatli)
  int? _vMatch; // yuz mosligi %
  final _tts = AudioPlayer(); // natijani ovozда aytish

  void _pick(String m) {
    setState(() {
      _method = m;
      _error = null;
      _searched = false;
      _records = const [];
      _qrUrl = null;
      _qrError = null;
      _qrPolling = false;
      _faceMode = false;
      _verifyError = null;
      _profile = null;
      _vCode = null;
      _vMatch = null;
    });
    if (m == 'qr') _startMyId();
  }

  /// In-page kameradan olingan yuz fotosi → MyID embedded (yuzni davlat bazasi
  /// bilan solishtiradi) → moslik bo'lsa to'liq profil + noqonuniy holat.
  Future<void> _runVerify(Map<String, String> L, String photo) async {
    setState(() {
      _faceMode = false;
      _loading = true;
      _verifyError = null;
    });
    final repo = ref.read(illegalRepoProvider);
    try {
      final r = _method == 'jshshir'
          ? await repo.verifyFace(mode: 'jshshir', jshshir: _jshshir.text.replaceAll(RegExp(r'\D'), ''), photo: photo)
          : await repo.verifyFace(mode: 'passport', passport: _pass.text.replaceAll(' ', ''), birth: _birth.text.trim(), photo: photo);
      if (!mounted) return;
      if (r['verified'] == true) {
        final recs = (r['records'] as List? ?? [])
            .map((e) => IllegalRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        setState(() {
          _profile = (r['profile'] is Map) ? Map<String, dynamic>.from(r['profile'] as Map) : null;
          _vCode = (r['code'] is num) ? (r['code'] as num).toInt() : 1;
          _vMatch = (r['match'] is num) ? (r['match'] as num).toInt() : (_profile?['match'] is num ? (_profile!['match'] as num).toInt() : null);
          _records = recs;
          _searched = true;
          _loading = false;
        });
        _say(recs.isEmpty ? (L['voiceOkClean'] ?? '') : (L['voiceOkViol'] ?? '')); // muvaffaqiyat ovozи
      } else {
        setState(() {
          _verifyError = (r['error']?.toString()) ?? 'MyID xato';
          _loading = false;
        });
        _say(L['voiceFail'] ?? ''); // yuz mos kelmadi ovozи
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifyError = 'Xato: $e';
          _loading = false;
        });
      }
    }
  }

  /// Natijani ovozда aytadi (server TTS → audioplayers).
  Future<void> _say(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final lang = ref.read(localeProvider);
      final voice = (lang == 'ru') ? 'madina' : 'sardor';
      final url = '${Env.apiBase}/tts/synthesize?text=${Uri.encodeComponent(text)}&voice=$voice&lang=$lang';
      await _tts.stop();
      await _tts.play(UrlSource(url));
    } catch (_) {}
  }

  Future<void> _startMyId() async {
    final L = illI18n[ref.read(localeProvider)]!;
    Map<String, dynamic> s;
    try {
      s = await ref.read(myidRepoProvider).startSession();
    } catch (_) {
      if (mounted) setState(() => _qrError = L['qrErr']);
      return;
    }
    final url = s['auth_url'] as String?;
    final st = s['state'] as String?;
    if (url == null || st == null) {
      if (mounted) setState(() => _qrError = (s['error']?.toString()) ?? L['qrErr']);
      return;
    }
    setState(() {
      _qrUrl = url;
      _qrPolling = true;
    });
    final repo = ref.read(myidRepoProvider);
    final t0 = DateTime.now();
    while (mounted && _qrPolling && _method == 'qr' && DateTime.now().difference(t0).inSeconds < 180) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_qrPolling) return;
      Map<String, dynamic> r;
      try {
        r = await repo.myRecord(st);
      } catch (_) {
        continue;
      }
      if (r['ready'] != true) continue;
      _qrPolling = false;
      if (r['error'] != null) {
        if (mounted) setState(() => _qrError = L['qrErr']);
        return;
      }
      final recs = (r['records'] as List? ?? [])
          .map((e) => IllegalRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mounted) {
        setState(() {
          _qrUrl = null;
          _records = recs;
          _searched = true;
          _profile = (r['profile'] is Map) ? Map<String, dynamic>.from(r['profile'] as Map) : null;
          _vCode = 1;
          _vMatch = (_profile?['match'] is num) ? (_profile!['match'] as num).toInt() : null;
        });
        final l2 = illI18n[ref.read(localeProvider)]!;
        _say(recs.isEmpty ? (l2['voiceOkClean'] ?? '') : (l2['voiceOkViol'] ?? ''));
      }
      return;
    }
    _qrPolling = false;
  }

  @override
  void dispose() {
    _jshshir.dispose();
    _birth.dispose();
    _pass.dispose();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final L = illI18n[ref.watch(localeProvider)]!;
    final summary = ref.watch(illegalSummaryProvider);

    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // header: back + title/sub + total stats card
          Row(
            children: [
              Press(
                scale: 0.92,
                onTap: () => context.go('/'),
                child: Container(
                  width: 74,
                  height: 74,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: T.line, width: 1.5),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: T.shadow,
                  ),
                  child: const Text('‹', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: T.navy)),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['pIllegal'], style: K.pgTitle),
                    const SizedBox(height: 4),
                    Text(L['sub']!, style: K.pgSub),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              summary.maybeWhen(
                data: (s) => _StatsCard(total: s.total, label: L['totalLbl']!, count: L['count']!),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Center(child: Text(L['choose']!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: T.navy))),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _MethodBtn(icon: Icons.badge_outlined, label: L['mJshshir']!, color: T.blue, onTap: () => _pick('jshshir'))),
              const SizedBox(width: 16),
              Expanded(child: _MethodBtn(icon: Icons.menu_book_outlined, label: L['mPassport']!, color: T.blue, onTap: () => _pick('passport'))),
              const SizedBox(width: 16),
              Expanded(child: _MethodBtn(icon: Icons.qr_code_2, label: L['mQr']!, color: T.green, onTap: () => _pick('qr'))),
            ],
          ),
          const SizedBox(height: 18),
          _form(L),
          if (_verifyError != null)
            KCard(
              accent: T.recRed,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('❌ MyID', style: K.cardH.copyWith(color: T.recRed)),
                const SizedBox(height: 8),
                SelectableText(_verifyError!, style: K.cardP),
              ]),
            ),
          _resultView(L),
          // Tuman jadvали FAQAT tekshiruvdан oldin (natija chiqsa yashiriladi)
          if (!_searched) ...[
            const SizedBox(height: 18),
            AsyncView(summary, data: (s) => GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 5.0,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final d in s.districts) _IllTile(d: d, count: L['count']!)],
            )),
          ],
        ],
      ),
    );
  }

  Widget _form(Map<String, String> L) {
    if (_method == null) return const SizedBox.shrink();
    if (_method == 'qr') {
      if (_qrError != null) return KCard(accent: T.recRed, child: Text(_qrError!, style: K.cardP));
      if (_qrUrl == null) {
        return const KCard(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: T.blue))));
      }
      return KCard(
        child: Column(
          children: [
            const Text('🪪 MyID', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.blue)),
            const SizedBox(height: 8),
            Text(L['qrScan']!, textAlign: TextAlign.center, style: K.cardP),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: T.line, width: 2), borderRadius: BorderRadius.circular(14)),
              child: QrImageView(
                data: _qrUrl!,
                size: 300,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: T.navy),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: T.navy),
              ),
            ),
            const SizedBox(height: 12),
            Text(L['qrWait']!, style: K.distCount),
            const SizedBox(height: 14),
            KButton(L['cancel']!, variant: 'outline', onTap: () => setState(() {
              _qrPolling = false;
              _method = null;
              _qrUrl = null;
            })),
          ],
        ),
      );
    }
    // JSHSHIR/Pasport: in-page native kamera (yuzni o'sha sahifada oladi)
    if (_faceMode) {
      return FaceCapture(
        t: L,
        onCancel: () => setState(() => _faceMode = false),
        onCaptured: (photo) => _runVerify(L, photo),
      );
    }
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_method == 'jshshir')
            KField(controller: _jshshir, label: L['fJshshir'], hint: L['jshshirPh'])
          else ...[
            KField(controller: _birth, label: L['birthLbl'], hint: L['birthPh']),
            const SizedBox(height: 14),
            KField(controller: _pass, label: L['passLbl'], hint: L['passPh']),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: T.errText, fontSize: 20)),
          ],
          const SizedBox(height: 14),
          // submit → o'sha sahifada kamera ochiladi (in-page Face-ID → MyID embedded)
          KButton(_loading ? L['verifying']! : L['submit']!, onTap: () {
            if (_loading) return;
            if (_method == 'jshshir') {
              final j = _jshshir.text.replaceAll(RegExp(r'\D'), '');
              if (j.length < 14) {
                setState(() => _error = L['errJshshir']);
                return;
              }
            } else {
              final b = _birth.text.trim();
              final p = _pass.text.replaceAll(' ', '');
              if (b.isEmpty || p.length < 7) {
                setState(() => _error = L['errPass']);
                return;
              }
            }
            setState(() {
              _error = null;
              _faceMode = true;
            });
          }),
        ],
      ),
    );
  }

  // Jins kodi → so'z. 1=Erkak, boshqa har qanday (bo'sh emas)=Ayol.
  String _genderLabel(dynamic g, Map<String, String> L) {
    final s = (g ?? '').toString().trim();
    if (s.isEmpty) return '';
    return s == '1' ? (L['genderMale'] ?? 'Erkak') : (L['genderFemale'] ?? 'Ayol');
  }

  // Tekshiruv natijasi kartasi (shield + holat + yuz mosligi + kod + izoh)
  Widget _statusCard(Map<String, String> L) {
    final ok = (_vCode ?? 1) == 1;
    final note = _noteFor(_vCode ?? 1, L);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFEFF8F2) : const Color(0xFFFDEEEE),
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: ok ? const Color(0x331FA463) : const Color(0x33E5484D), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(color: ok ? T.green : T.recRed, shape: BoxShape.circle),
            child: Icon(ok ? Icons.verified_user_rounded : Icons.gpp_bad_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L['resultTitle'] ?? 'Tekshiruv natijasi',
                    style: K.cardH.copyWith(color: ok ? T.green : T.recRed)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${L['resultState'] ?? 'Holati'}: ', style: K.cardP.copyWith(color: T.muted)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(color: ok ? T.green : T.recRed, borderRadius: BorderRadius.circular(20)),
                        child: Text(ok ? (L['resultOk'] ?? 'Muvaffaqiyatli') : (L['resultBad'] ?? 'Muvaffaqiyatsiz'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                      ),
                    ]),
                    if (_vMatch != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${L['pMatch'] ?? 'Yuz mosligi'}: ', style: K.cardP.copyWith(color: T.muted)),
                        Text('$_vMatch%', style: K.cardP.copyWith(color: T.green, fontWeight: FontWeight.w800)),
                      ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${L['resultCode'] ?? 'Kod'}: ', style: K.cardP.copyWith(color: T.muted)),
                      Text('${_vCode ?? 1}', style: K.cardP.copyWith(color: ok ? T.green : T.recRed, fontWeight: FontWeight.w800)),
                    ]),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${L['resultNote'] ?? 'Izoh'}: $note', style: K.cardP),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _noteFor(int code, Map<String, String> L) {
    switch (code) {
      case 1: return L['note1'] ?? 'Barcha tekshiruvlar muvaffaqiyatli yakunlandi.';
      case 2: return L['note2'] ?? 'Pasport ma’lumotlari noto‘g‘ri.';
      case 3: return L['note3'] ?? 'Jonlilik tasdiqlanmadi.';
      case 4: return L['note4'] ?? 'Yuz tanib bo‘lmadi.';
      default: return '';
    }
  }

  // Shaxs ma'lumotlari (ikonкali qatorlar — faqat to'ldirilgan maydonlar)
  Widget _personCard(Map<String, String> L, Map<String, dynamic> p) {
    final items = <(IconData, String, String)>[];
    void add(IconData ic, String label, dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty && s != 'null') items.add((ic, label, s));
    }
    add(Icons.person_outline, L['fFio']!, p['name']);
    add(Icons.tag, L['fJshshir']!, p['pinfl']);
    add(Icons.badge_outlined, L['fPassport']!, p['passport']);
    add(Icons.wc_outlined, L['pGender']!, _genderLabel(p['gender'], L));
    add(Icons.calendar_today_outlined, L['pBirthDate']!, p['birth_date']);
    add(Icons.location_on_outlined, L['pBirthPlace']!, p['birth_place']);
    add(Icons.public, L['pNationality']!, p['nationality']);
    add(Icons.flag_outlined, L['pCitizenship'] ?? 'Fuqaroligi', p['citizenship']);
    add(Icons.description_outlined, L['pDocType'] ?? 'Hujjat turi', p['doc_type']);
    add(Icons.account_balance_outlined, L['pPassIssuedBy'] ?? 'Kim bergan', p['pass_issued_by']);
    add(Icons.event_available_outlined, L['pPassIssuedDate'] ?? 'Berilgan sana', p['pass_issued_date']);
    add(Icons.event_busy_outlined, L['pPassExpiry'] ?? 'Amal muddati', p['pass_expiry_date']);
    add(Icons.map_outlined, L['fRegion']!, p['region']);
    add(Icons.location_city_outlined, L['fDistrict']!, p['district']);
    add(Icons.home_outlined, L['fMahalla']!, p['mfy']);
    add(Icons.place_outlined, L['pAddress']!, p['address']);
    add(Icons.phone_outlined, L['pPhone']!, p['phone']);
    return KCard(
      accent: T.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(color: T.blue, shape: BoxShape.circle),
              child: const Icon(Icons.person, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Text(L['profileTitle'] ?? 'Shaxs ma’lumotlari', style: K.cardH.copyWith(color: T.blue)),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: i == items.length - 1 ? null : const Border(bottom: BorderSide(color: T.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(items[i].$1, color: T.blue, size: 28),
                  const SizedBox(width: 18),
                  SizedBox(width: 190, child: Text(items[i].$2, style: K.cardP.copyWith(color: T.muted))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(items[i].$3, style: K.cardP.copyWith(fontWeight: FontWeight.w700, color: T.navy))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultView(Map<String, String> L) {
    if (!_searched) return const SizedBox.shrink();
    final p = _profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p != null) ...[
          _statusCard(L),
          const SizedBox(height: 18),
          _personCard(L, p),
        ],
        // violation status
        if (_records.isEmpty)
          KCard(accent: T.green, child: Row(children: [
            const Icon(Icons.check_circle, color: T.green, size: 34),
            const SizedBox(width: 14),
            Expanded(child: Text(L['noViolation']!, style: K.cardP.copyWith(color: T.green, fontWeight: FontWeight.w700))),
          ]))
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('⚠️ ${L['violTitle']}', style: K.cardH.copyWith(color: T.recRed)),
          ),
          for (final r in _records)
            KCard(
              accent: T.recRed,
              child: KvRows([
                (L['fFio']!, r.fio),
                (L['fJshshir']!, r.jshshir),
                (L['fPassport']!, r.passport),
                (L['fRegion']!, r.viloyat),
                (L['fDistrict']!, r.tumanFull.isEmpty ? r.tuman : r.tumanFull),
                (L['fMahalla']!, r.mahalla),
                (L['fArea']!, r.area.isEmpty ? '' : '${r.area} m²'),
                (L['fType']!, r.tur),
                (L['fModda']!, r.modda),
                (L['fStatus']!, r.inner.isEmpty ? r.status : r.inner),
                (L['fKadastr']!, r.kadastr),
                (L['fDate']!, r.sana),
              ]),
            ),
        ],
      ],
    );
  }
}

class _IllTile extends StatelessWidget {
  const _IllTile({required this.d, required this.count});
  final IllegalDistrict d;
  final String count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: T.line, width: 1.5),
        borderRadius: BorderRadius.circular(T.rCard),
        boxShadow: T.shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFFF1F4F9), shape: BoxShape.circle),
            child: kIcon('pin', size: 28, color: T.green, stroke: 1.8),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(d.display, style: K.distName, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          Text.rich(TextSpan(children: [
            TextSpan(text: fmt(d.count), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.blue)),
            TextSpan(text: ' $count', style: const TextStyle(fontSize: 19, color: T.muted)),
          ])),
        ],
      ),
    );
  }
}

/// One of the 3 verification-method buttons (icon + label + chevron).
class _MethodBtn extends StatelessWidget {
  const _MethodBtn({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Press(
      scale: 0.97,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(T.rBtn)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white))),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 28),
          ],
        ),
      ),
    );
  }
}

/// Total stats card in the header (people icon + count + label).
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.total, required this.label, required this.count});
  final int total;
  final String label, count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: T.line, width: 1.5),
        borderRadius: BorderRadius.circular(T.rCard),
        boxShadow: T.shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups, color: T.blue, size: 44),
          const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: fmt(total), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: T.blue)),
                TextSpan(text: ' $count', style: const TextStyle(fontSize: 22, color: T.muted)),
              ])),
              Text(label, style: const TextStyle(fontSize: 20, color: T.muted)),
            ],
          ),
        ],
      ),
    );
  }
}
