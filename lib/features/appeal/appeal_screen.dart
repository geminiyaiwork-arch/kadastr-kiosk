import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_win/video_player_win.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/repository.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/kiosk_shell.dart';
import '../common/kfield.dart';
import '../common/widgets.dart';

/// Murojaat yuborish — shaxsiy ma'lumot + jins + bo'lim/xodim + VIDEO yozish + telefon (MAJBURIY).
/// Qaysi xodimga yo'llasa — o'sha xodim hisobiga (predlojeniyasiga) tushadi.
class AppealScreen extends ConsumerStatefulWidget {
  const AppealScreen({super.key});
  @override
  ConsumerState<AppealScreen> createState() => _AppealScreenState();
}

class _AppealScreenState extends ConsumerState<AppealScreen> {
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _patronymic = TextEditingController();
  final _year = TextEditingController();
  final _phone = TextEditingController();
  final _text = TextEditingController();
  String _gender = ''; // 'male' | 'female'
  int? _deptId;
  String _deptName = '';
  int? _empId;

  // Video
  CameraController? _cam;
  bool _camOpen = false, _recording = false;
  String? _videoPath;
  WinVideoPlayerController? _review;

  bool _loading = false, _err = false, _sendFail = false;
  String? _sentId;

  @override
  void dispose() {
    for (final c in [_name, _surname, _patronymic, _year, _phone, _text]) c.dispose();
    _cam?.dispose();
    _review?.dispose();
    super.dispose();
  }

  // ---- Video yozish ----
  Future<void> _openCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.medium, enableAudio: true);
      await c.initialize();
      if (!mounted) return;
      setState(() { _cam = c; _camOpen = true; });
    } catch (_) {
      _toast(ref.read(trProvider)['apVideoNo'] ?? 'Kamera mavjud emas — matn bilan yuboring');
    }
  }

  Future<void> _startRec() async {
    final c = _cam;
    if (c == null || _recording) return;
    try { await c.startVideoRecording(); setState(() => _recording = true); } catch (_) {}
  }

  Future<void> _stopRec() async {
    final c = _cam;
    if (c == null || !_recording) return;
    try {
      final f = await c.stopVideoRecording();
      _recording = false;
      await c.dispose();
      _cam = null; _camOpen = false;
      _videoPath = f.path;
      final r = WinVideoPlayerController.file(File(f.path));
      await r.initialize();
      if (r.value.isInitialized) { r.setLooping(true); await r.play(); }
      if (mounted) setState(() => _review = r);
    } catch (_) {
      if (mounted) setState(() { _recording = false; _camOpen = false; });
    }
  }

  Future<void> _resetVideo() async {
    try { await _review?.dispose(); } catch (_) {}
    try { if (_videoPath != null) File(_videoPath!).deleteSync(); } catch (_) {}
    setState(() { _review = null; _videoPath = null; });
  }

  void _cancelCamera() {
    try { _cam?.dispose(); } catch (_) {}
    setState(() { _cam = null; _camOpen = false; _recording = false; });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send() async {
    if (_loading) return;
    // TELEFON MAJBURIY
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 7) { setState(() => _err = true); return; }
    if (_text.text.trim().isEmpty && _videoPath == null) { setState(() => _err = true); return; }
    setState(() { _loading = true; _err = false; _sendFail = false; });
    String? videoB64, videoExt;
    try {
      if (_videoPath != null) {
        final bytes = await File(_videoPath!).readAsBytes();
        videoB64 = 'data:video/mp4;base64,${base64Encode(bytes)}';
        videoExt = _videoPath!.toLowerCase().endsWith('.mp4') ? 'mp4' : 'webm';
      }
    } catch (_) {}
    String? id;
    try {
      final r = await ref.read(dioProvider).post('/appeal', data: {
        'name': _name.text.trim(), 'surname': _surname.text.trim(), 'patronymic': _patronymic.text.trim(),
        'birth_year': _year.text.trim(), 'gender': _gender,
        'phone': _phone.text.trim(), 'text': _text.text.trim(),
        'department': _deptName, 'employee_id': _empId,
        'mode': _videoPath != null ? 'video' : 'text', 'lang': ref.read(localeProvider),
        if (videoB64 != null) 'video': videoB64, if (videoExt != null) 'videoExt': videoExt,
      });
      id = (Map<String, dynamic>.from(r.data as Map)['id'] ?? '').toString();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (id != null && id.isNotEmpty) { _sentId = id; } else { _sendFail = true; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    if (_sentId != null) {
      return KioskScaffold(body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHead(t['pAppeal'], sub: t['apSub']),
        KCard(accent: T.green, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('✓ ${t['apOk']}', style: K.cardH.copyWith(color: T.green)),
          const SizedBox(height: 12),
          KvRows([(t['apNum'] as String, _sentId!)]),
          const SizedBox(height: 12),
          Text(t['apThanks'], style: K.cardP),
        ])),
      ]));
    }
    final depts = ref.watch(departmentsProvider).asData?.value ?? const [];
    final emps = ref.watch(employeesProvider).asData?.value ?? const [];
    return KioskScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(t['pAppeal'], sub: t['apSub']),
          // 1) Shaxsiy ma'lumot
          KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl(t['apPersonal'] ?? 'Shaxsiy ma’lumot'),
            KField(controller: _name, label: t['apFirstName'] ?? 'Ism'),
            const SizedBox(height: 12),
            KField(controller: _surname, label: t['apLastName'] ?? 'Familiya'),
            const SizedBox(height: 12),
            KField(controller: _patronymic, label: t['apPatronymic'] ?? 'Otasining ismi'),
            const SizedBox(height: 12),
            KField(controller: _year, label: t['apBirthYear'] ?? 'Tug‘ilgan yil', hint: '1990'),
            const SizedBox(height: 14),
            Text(t['apGender'] ?? 'Jinsi', style: K.fLabel),
            const SizedBox(height: 8),
            Row(children: [
              _genderChip(t['apMale'] ?? 'Erkak', 'male', Icons.man_rounded),
              const SizedBox(width: 12),
              _genderChip(t['apFemale'] ?? 'Ayol', 'female', Icons.woman_rounded),
            ]),
            const SizedBox(height: 14),
            KField(controller: _phone, label: '${t['recPhone']} *', hint: '+998'),
          ])),
          const SizedBox(height: 14),
          // 2) Kimga
          KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl(t['apTo'] ?? 'Murojaat kimga'),
            _dropdown<int>(
              label: t['apDept'] ?? 'Bo‘lim',
              value: _deptId,
              items: [for (final d in depts) DropdownMenuItem(value: d['id'] as int?, child: Text('${d['name']}'))],
              onChanged: (v) => setState(() { _deptId = v; _deptName = depts.firstWhere((d) => d['id'] == v, orElse: () => {'name': ''})['name']?.toString() ?? ''; }),
            ),
            if (emps.isNotEmpty) ...[
              const SizedBox(height: 12),
              _dropdown<int>(
                label: t['apEmployee'] ?? 'Xodim (ixtiyoriy)',
                value: _empId,
                items: [const DropdownMenuItem(value: null, child: Text('—')), for (final e in emps) DropdownMenuItem(value: e.id, child: Text(e.name))],
                onChanged: (v) => setState(() => _empId = v),
              ),
            ],
          ])),
          const SizedBox(height: 14),
          // 3) Video
          KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl(t['apVideo'] ?? 'Video murojaat (ixtiyoriy)'),
            _videoSection(t),
          ])),
          const SizedBox(height: 14),
          // 4) Matn
          KCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KField(controller: _text, label: t['apText'], hint: t['apTextHint'], lines: 4),
          ])),
          if (_err) ...[const SizedBox(height: 10), Text(t['apNeedFull'] ?? 'Telefon (majburiy) va matn yoki video kiriting', style: K.cardP.copyWith(color: T.errText))],
          if (_sendFail) ...[const SizedBox(height: 10), Text(t['apFail'], style: K.cardP.copyWith(color: T.errText))],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: KButton(t['cancel'] ?? 'Bekor qilish', variant: 'outline', onTap: () => Navigator.of(context).maybePop())),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: KButton(_loading ? '…' : (t['apSend']), onTap: _send)),
          ]),
        ],
      ),
    );
  }

  Widget _lbl(String s) => Padding(padding: const EdgeInsets.only(bottom: 12),
      child: Text(s, style: const TextStyle(color: T.navy, fontSize: 22, fontWeight: FontWeight.w800)));

  Widget _genderChip(String label, String val, IconData ic) {
    final on = _gender == val;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _gender = val),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: on ? T.green : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? T.green : T.line, width: 2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, color: on ? Colors.white : T.muted, size: 26),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: on ? Colors.white : T.navy, fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      ),
    ));
  }

  Widget _dropdown<X>({required String label, required X? value, required List<DropdownMenuItem<X>> items, required ValueChanged<X?> onChanged}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: K.fLabel),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border.all(color: T.line, width: 2), borderRadius: BorderRadius.circular(T.rInput)),
          child: DropdownButton<X>(value: value, isExpanded: true, underline: const SizedBox.shrink(), style: K.fInput, items: items, onChanged: onChanged),
        ),
      ]);

  Widget _videoSection(Map<String, dynamic> t) {
    // Yozib bo'lingan — ko'rish (loop) + qayta
    if (_review != null && _review!.value.isInitialized) {
      return Column(children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(
          aspectRatio: _review!.value.aspectRatio > 0 ? _review!.value.aspectRatio : 16 / 9,
          child: WinVideoPlayer(_review!),
        )),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.check_circle_rounded, color: T.green, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(t['apVideoReady'] ?? 'Video tayyor — "Yuborish" bosing yoki qayta yozing', style: K.pgSub)),
          KButton(t['apRetry'] ?? 'Qayta', variant: 'outline', onTap: _resetVideo),
        ]),
      ]);
    }
    // Kamera ochiq — yozish/to'xtatish
    if (_camOpen && _cam != null && _cam!.value.isInitialized) {
      return Column(children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: 16 / 9, child: CameraPreview(_cam!))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: KButton(
            _recording ? (t['apStop'] ?? '■ To‘xtatish') : (t['apRec'] ?? '● Yozishni boshlash'),
            onTap: _recording ? _stopRec : _startRec)),
          const SizedBox(width: 12),
          KButton(t['cancel'] ?? 'Bekor', variant: 'outline', onTap: _cancelCamera),
        ]),
      ]);
    }
    // Boshlang'ich — video yozish tugmasi
    return KButton(t['apVideoStart'] ?? '🎥 Video yozib qoldirish', variant: 'outline', onTap: _openCamera);
  }
}
