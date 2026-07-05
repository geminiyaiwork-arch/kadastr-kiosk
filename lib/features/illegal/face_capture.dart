import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../common/widgets.dart';

/// Face capture for kiosk Face-ID (MyID embedded).
/// Yo'riqli JONLI avto-suratga olish: kamera ochilгач tizim O'ZI yuzни markazlashtirishни
/// so'raydi → sekin tepaga/o'ngga/chapga qarash yo'riqlari (jonlilik tuyg'usi) → "to'g'ri
/// qarang" + 3-2-1 sanoq → AVTOMATIK suratga oladi (tugma yo'q) → onCaptured orqali darhol
/// MyID tekshiruviga yuboriladi. Haqiqiy yuz-solishtiruv + jonlilikни MyID serveri qiladi.
/// - Windows/macOS: native `camera` paketi (sahifa ichида preview).
/// - Linux: bundlangan `myid-camera` WebKitGTK helper.
class FaceCapture extends StatefulWidget {
  const FaceCapture({super.key, required this.t, required this.onCaptured, required this.onCancel});
  final Map<String, String> t;
  final void Function(String photoDataUri) onCaptured;
  final VoidCallback onCancel;
  @override
  State<FaceCapture> createState() => _FaceCaptureState();
}

class _FaceCaptureState extends State<FaceCapture> with SingleTickerProviderStateMixin {
  CameraController? _cam;
  bool _noCamera = false;
  bool _busy = false;
  bool _failed = false; // suratga olishда xato — qayta urinish
  bool _linuxRunning = false; // Linux helper oynasi ochiq
  bool _cancelled = false; // dispose/bekor — oqim to'xtaydi
  bool _flowStarted = false;

  late final AnimationController _ring; // aylanuvchi skaner halqasi
  String _hint = '';
  IconData? _hintIcon;
  int _countdown = 0; // >0 bo'lsa markazда katta raqam

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
    _hint = widget.t['faceStepCenter'] ?? 'Yuzingizni doira ichiga joylang';
    if (Platform.isLinux) {
      _linuxCapture();
    } else {
      _init();
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _ring.dispose();
    _cam?.dispose();
    super.dispose();
  }

  /// Linux: bundlangan WebKitGTK helper (fullscreen kamera) → rasm faylга → o'qib uzatamiz.
  Future<void> _linuxCapture() async {
    final helper = '${File(Platform.resolvedExecutable).parent.path}/myid-camera';
    if (!File(helper).existsSync()) {
      if (mounted) setState(() => _noCamera = true);
      return;
    }
    final out = '${Directory.systemTemp.path}/myid_face_${DateTime.now().millisecondsSinceEpoch}.txt';
    if (mounted) setState(() => _linuxRunning = true);
    try {
      await Process.run(helper, [out]);
      final f = File(out);
      String? photo;
      if (f.existsSync()) {
        final s = (await f.readAsString()).trim();
        if (s.startsWith('data:image')) photo = s;
        try { f.deleteSync(); } catch (_) {}
      }
      if (!mounted) return;
      if (photo != null) {
        widget.onCaptured(photo);
      } else {
        widget.onCancel();
      }
    } catch (_) {
      if (mounted) setState(() { _linuxRunning = false; _noCamera = true; });
    }
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) { setState(() => _noCamera = true); return; }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final c = CameraController(front, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() => _cam = c);
      _startFlow();
    } catch (_) {
      if (mounted) setState(() => _noCamera = true);
    }
  }

  void _startFlow() {
    if (_flowStarted) return;
    _flowStarted = true;
    _runFlow();
  }

  /// Yo'riqli jonlilik ketma-ketligi → avtomatik suratga olish (tugmasiz).
  Future<void> _runFlow() async {
    final t = widget.t;
    final steps = <(String, IconData, int)>[
      (t['faceStepCenter'] ?? 'Yuzingizni doira ichiga joylang', Icons.center_focus_strong_rounded, 1500),
      (t['faceStepUp'] ?? 'Boshingizni sekin tepaga', Icons.keyboard_arrow_up_rounded, 950),
      (t['faceStepRight'] ?? 'Sekin o‘ngga buring', Icons.keyboard_arrow_right_rounded, 950),
      (t['faceStepLeft'] ?? 'Sekin chapga buring', Icons.keyboard_arrow_left_rounded, 950),
      (t['faceStepFront'] ?? 'Endi to‘g‘ri qarang', Icons.face_retouching_natural_rounded, 950),
    ];
    for (final s in steps) {
      if (!mounted || _cancelled) return;
      setState(() { _hint = s.$1; _hintIcon = s.$2; _countdown = 0; });
      await Future.delayed(Duration(milliseconds: s.$3));
    }
    for (var n = 3; n >= 1; n--) {
      if (!mounted || _cancelled) return;
      setState(() { _hint = t['faceHold'] ?? 'To‘g‘ri qarang'; _hintIcon = null; _countdown = n; });
      await Future.delayed(const Duration(milliseconds: 650));
    }
    if (!mounted || _cancelled) return;
    await _capture();
  }

  Future<void> _capture() async {
    final c = _cam;
    if (c == null || _busy) return;
    setState(() { _busy = true; _countdown = 0; _hint = widget.t['verifying'] ?? 'Tekshirilmoqda…'; _hintIcon = null; });
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted || _cancelled) return;
      widget.onCaptured('data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (_) {
      if (mounted) setState(() { _busy = false; _failed = true; });
    }
  }

  void _retry() {
    setState(() { _failed = false; _flowStarted = false; _busy = false; _countdown = 0; });
    _startFlow();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ready = _cam?.value.isInitialized ?? false;

    if (_linuxRunning) {
      return KCard(child: Column(children: [
        Text(t['faceTitle']!, textAlign: TextAlign.center, style: K.cardH),
        const SizedBox(height: 18),
        const CircularProgressIndicator(color: T.blue),
        const SizedBox(height: 18),
        Text(t['faceWindowOpen'] ?? 'Kamera oynasi ochildi — yuzingizni suratga oling.',
            textAlign: TextAlign.center, style: K.cardP),
        const SizedBox(height: 14),
        KButton(t['cancel']!, variant: 'outline', onTap: widget.onCancel),
      ]));
    }

    return KCard(
      child: Column(children: [
        Text(t['faceTitle']!, textAlign: TextAlign.center, style: K.cardH),
        const SizedBox(height: 6),
        Text(t['faceAuto'] ?? 'Tizim yuzingizni avtomatik suratga oladi — qimirlamang',
            textAlign: TextAlign.center, style: K.pgSub),
        const SizedBox(height: 18),
        if (ready)
          _circle()
        else if (_noCamera)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: T.errBg, borderRadius: BorderRadius.circular(14)),
            child: Text(t['faceNoCam']!, textAlign: TextAlign.center, style: K.cardP.copyWith(color: T.errText)),
          )
        else
          const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: T.blue)),
        const SizedBox(height: 18),
        if (ready && !_failed)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_busy ? Icons.verified_rounded : Icons.center_focus_weak_rounded, color: T.green, size: 24),
            const SizedBox(width: 10),
            Flexible(child: Text(_hint, textAlign: TextAlign.center,
                style: K.cardH.copyWith(fontSize: 22, color: _busy ? T.green : T.navy))),
          ]),
        if (_failed) ...[
          Text(t['faceRetryMsg'] ?? 'Suratga olib bo‘lmadi. Qayta urinib ko‘ring.',
              textAlign: TextAlign.center, style: K.cardP.copyWith(color: T.errText)),
          const SizedBox(height: 12),
          KButton(t['faceRetry'] ?? 'Qayta urinish', onTap: _retry),
        ],
        const SizedBox(height: 12),
        KButton(t['cancel']!, variant: 'outline', onTap: () { _cancelled = true; widget.onCancel(); }),
      ]),
    );
  }

  /// Aylanuvchi skaner-halqa + cho'zilmagan (cover) doira preview + sanoq.
  Widget _circle() {
    final ps = _cam!.value.previewSize;
    final pw = ps?.width ?? 1280.0;
    final ph = ps?.height ?? 720.0;
    return SizedBox(
      width: 360, height: 360,
      child: Stack(alignment: Alignment.center, children: [
        // aylanuvchi gradient halqa (skaner)
        RotationTransition(
          turns: _ring,
          child: Container(
            width: 360, height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: [
                T.green.withOpacity(0.0), T.green, T.blue, T.green.withOpacity(0.0),
              ]),
            ),
          ),
        ),
        // kamera preview — ASPECT saqlanadi (cho'zilmaydi), doiraга cover
        ClipOval(
          child: SizedBox(
            width: 340, height: 340,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: pw, height: ph, child: CameraPreview(_cam!)),
            ),
          ),
        ),
        // yo'nalish ishorasi (jonlilik) — pastда
        if (_hintIcon != null && _countdown == 0 && !_busy)
          Positioned(
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.34), shape: BoxShape.circle),
              child: Icon(_hintIcon, color: Colors.white, size: 40),
            ),
          ),
        // sanoq (3-2-1) markazда
        if (_countdown > 0)
          Container(
            width: 340, height: 340, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.30)),
            child: Text('$_countdown', style: const TextStyle(fontSize: 128, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
      ]),
    );
  }
}
