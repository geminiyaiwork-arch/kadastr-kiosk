import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  String? _facePhoto; // kameradan olingan yuz fotosi (natijada ko'rsatamiz)

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
      _facePhoto = null;
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
          _facePhoto = photo; // kamera fotosini natijada ko'rsatamiz
          _records = recs;
          _searched = true;
          _loading = false;
        });
      } else {
        setState(() {
          _verifyError = (r['error']?.toString()) ?? 'MyID xato';
          _loading = false;
        });
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
        });
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

  // Jins kodi → so'z (1=Erkak, 2=Ayol)
  String _genderLabel(dynamic g, Map<String, String> L) {
    final s = (g ?? '').toString().trim().toLowerCase();
    if (s == '1' || s == 'male' || s == 'м' || s == 'm') return L['genderMale'] ?? 'Erkak';
    if (s == '2' || s == 'female' || s == 'ж' || s == 'f') return L['genderFemale'] ?? 'Ayol';
    return (g ?? '').toString().trim();
  }

  Widget _profileCard(Map<String, String> L, Map<String, dynamic> p) {
    Uint8List? bytes;
    final ph = _facePhoto;
    if (ph != null && ph.contains(',')) {
      try { bytes = base64Decode(ph.split(',').last); } catch (_) {}
    }
    final match = p['match'];
    final rows = <(String, String)>[];
    void add(String label, dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty && s != 'null') rows.add((label, s));
    }
    add(L['fJshshir']!, p['pinfl']);
    add(L['fPassport']!, p['passport']);
    add(L['pBirthDate']!, p['birth_date']);
    add(L['pBirthPlace']!, p['birth_place']);
    add(L['pGender']!, _genderLabel(p['gender'], L));
    add(L['pNationality']!, p['nationality']);
    add(L['pCitizenship'] ?? 'Fuqarolik', p['citizenship']);
    add(L['pDocType'] ?? 'Hujjat turi', p['doc_type']);
    add(L['pPassIssuedBy'] ?? 'Kim tomonidan berilgan', p['pass_issued_by']);
    add(L['pPassIssuedDate'] ?? 'Berilgan sana', p['pass_issued_date']);
    add(L['pPassExpiry'] ?? 'Amal qilish muddati', p['pass_expiry_date']);
    add(L['fRegion']!, p['region']);
    add(L['fDistrict']!, p['district']);
    add(L['fMahalla']!, p['mfy']);
    add(L['pAddress']!, p['address']);
    add(L['pPhone']!, p['phone']);
    return KCard(
      accent: T.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: bytes != null
                    ? Image.memory(bytes, width: 130, height: 160, fit: BoxFit.cover, gaplessPlayback: true)
                    : Container(width: 130, height: 160, color: const Color(0xFFEFF3FA), child: const Icon(Icons.person, size: 70, color: T.muted)),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🪪 ${L['profileTitle']}', style: K.cardP.copyWith(color: T.muted, fontSize: 19)),
                    const SizedBox(height: 6),
                    Text('${p['name'] ?? ''}', style: K.cardH),
                    if (match != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFFE6F4EC), borderRadius: BorderRadius.circular(22)),
                        child: Text('✅ ${L['pMatch'] ?? 'Yuz mosligi'}: $match%',
                            style: const TextStyle(color: T.green, fontWeight: FontWeight.w800, fontSize: 19)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(color: T.line, height: 1)),
          KvRows(rows),
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
        if (p != null) _profileCard(L, p),
        // violation status
        if (_records.isEmpty)
          KCard(accent: T.green, child: Text('✅ ${L['noViolation']}', style: K.cardP.copyWith(color: T.green, fontWeight: FontWeight.w700)))
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
