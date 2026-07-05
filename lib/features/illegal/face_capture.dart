import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../common/widgets.dart';

/// AKTIV JONLILIK (liveness) yuz-tekshiruvi — kiosk O'ZI harakatni aniqlaydi.
/// Oqim: kamera kadrlarini serverga (MediaPipe: yaw/pitch/ear) yuboradi →
/// "Boshingizni o'ngga → chapga buring → ko'zingizni pirpirating → to'g'ri qarang"
/// qadamlarини REAL aniqlaydi (soxta foto o'tmaydi) → to'g'ri-frontal kadrni MyID'ga yuboradi.
/// Windows kiosk = `camera` paketi. Linux = bundlangan `myid-camera` helper (o'zgармаган).
class FaceCapture extends StatefulWidget {
  const FaceCapture({super.key, required this.t, required this.onCaptured, required this.onCancel});
  final Map<String, String> t;
  final void Function(String photoDataUri) onCaptured;
  final VoidCallback onCancel;
  @override
  State<FaceCapture> createState() => _FaceCaptureState();
}

class _FaceCaptureState extends State<FaceCapture> {
  CameraController? _cam;
  bool _noCamera = false;
  bool _linuxRunning = false;
  bool _cancelled = false;
  bool _busy = false; // takePicture jarayonда
  bool _done = false;
  Timer? _timer;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: Env.apiBase,
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
  ));

  // Holat-mashinasi: 0 kalibr, 1 yon burilish A, 2 yon B (teskari), 3 pirpirash, 4 to'g'ri→surat
  int _phase = 0;
  int _calibN = 0;
  double _baseYaw = 0, _basePitch = 0;
  int _turnSign = 0;
  bool _blinkClosed = false;
  bool _stepOk = false;
  int _straightCount = 0; // ketma-ket turg'un frontal kadrlar (bulanik surat oldini oladi)
  String _hint = '';

  @override
  void initState() {
    super.initState();
    _hint = widget.t['faceLoading'] ?? 'Kamera tayyorlanmoqda…';
    if (Platform.isLinux) {
      _linuxCapture();
    } else {
      _init();
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _timer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  // ---- Linux: bundlangan WebKitGTK helper (o'zgармаган) ----
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
      if (photo != null) { widget.onCaptured(photo); } else { widget.onCancel(); }
    } catch (_) {
      if (mounted) setState(() { _linuxRunning = false; _noCamera = true; });
    }
  }

  // ---- Windows/desktop kamera ----
  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) { setState(() => _noCamera = true); return; }
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() { _cam = c; _hint = widget.t['faceCalib'] ?? 'Tayyorlanmoqda…'; });
      _schedule(const Duration(milliseconds: 300));
    } catch (_) {
      if (mounted) setState(() => _noCamera = true);
    }
  }

  void _schedule(Duration d) {
    if (_cancelled || _done || !mounted) return;
    _timer = Timer(d, _tick);
  }

  Future<void> _tick() async {
    if (_cancelled || _done || !mounted) return;
    final c = _cam;
    if (c == null || _busy) { _schedule(const Duration(milliseconds: 250)); return; }
    _busy = true;
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      try { File(file.path).deleteSync(); } catch (_) {}
      Map<String, dynamic> m = const {};
      try {
        final r = await _dio.post('/liveness/analyze',
            data: {'image': 'data:image/jpeg;base64,${base64Encode(bytes)}'});
        if (r.data is Map) m = Map<String, dynamic>.from(r.data as Map);
      } catch (_) {}
      if (!mounted || _cancelled || _done) return;
      _process(m, bytes);
    } catch (_) {
      // kadr o'tkazib yuborildi
    } finally {
      _busy = false;
      _schedule(const Duration(milliseconds: 200));
    }
  }

  void _process(Map<String, dynamic> m, Uint8List bytes) {
    final face = m['face'] == true;
    final t = widget.t;
    if (!face) {
      setState(() => _hint = t['faceNoFace'] ?? 'Yuzingizni doira ichiga to‘g‘rilang');
      return;
    }
    final yaw = (m['yaw'] as num?)?.toDouble() ?? 0.0;
    final pitch = (m['pitch'] as num?)?.toDouble() ?? 0.0;
    final ear = (m['ear'] as num?)?.toDouble() ?? 0.3;

    switch (_phase) {
      case 0: // kalibratsiya (baseline)
        _baseYaw += yaw; _basePitch += pitch; _calibN++;
        setState(() => _hint = t['faceCalib'] ?? 'Tayyorlanmoqda…');
        if (_calibN >= 5) { _baseYaw /= _calibN; _basePitch /= _calibN; _advance(1); }
        break;
      case 1: // yon burilish (o'ngga)
        setState(() => _hint = t['faceTurnR'] ?? 'Boshingizni sekin O‘NGGA buring');
        final dy = yaw - _baseYaw;
        if (dy.abs() > 14) { _turnSign = dy > 0 ? 1 : -1; _advance(2); }
        break;
      case 2: // teskari yon (chapga)
        setState(() => _hint = t['faceTurnL'] ?? 'Endi sekin CHAPGA buring');
        final dy = yaw - _baseYaw;
        if (_turnSign != 0 && (dy > 0 ? 1 : -1) == -_turnSign && dy.abs() > 14) _advance(3);
        break;
      case 3: // pirpirash
        setState(() => _hint = t['faceBlink'] ?? 'Ko‘zingizni yuming va oching');
        if (ear < 0.17) _blinkClosed = true;
        if (_blinkClosed && ear > 0.26) _advance(4);
        break;
      case 4: // to'g'ri qarang + QIMIRLAMANG → SHARP frontal kadr → MyID
        final steady = (yaw - _baseYaw).abs() < 9 && (pitch - _basePitch).abs() < 13 && ear > 0.2;
        if (steady) {
          _straightCount++;
          // 3 ketma-ket turg'un kadr = bosh qimirlamayapti → surat aniq (bulanik emas)
          setState(() => _hint = t['faceStill'] ?? 'Qimirlamang…');
          if (_straightCount >= 3) {
            _done = true;
            _timer?.cancel();
            setState(() => _hint = t['verifying'] ?? 'Tekshirilmoqda…');
            widget.onCaptured('data:image/jpeg;base64,${base64Encode(bytes)}');
          }
        } else {
          _straightCount = 0;
          setState(() => _hint = t['faceHold'] ?? 'To‘g‘ri qarang');
        }
        break;
    }
  }

  void _advance(int p) {
    _phase = p;
    _blinkClosed = false;
    setState(() => _stepOk = true);
    Timer(const Duration(milliseconds: 700), () { if (mounted) setState(() => _stepOk = false); });
  }

  IconData _phaseIcon() {
    switch (_phase) {
      case 1: return Icons.chevron_right_rounded;
      case 2: return Icons.chevron_left_rounded;
      case 3: return Icons.remove_red_eye_rounded;
      case 4: return Icons.face_retouching_natural_rounded;
      default: return Icons.hourglass_bottom_rounded;
    }
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
        Text(t['faceLiveHint'] ?? 'Tizim jonliligingizni tekshiradi — ko‘rsatmalarga amal qiling',
            textAlign: TextAlign.center, style: K.pgSub),
        const SizedBox(height: 18),
        if (ready) _circle() else if (_noCamera)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: T.errBg, borderRadius: BorderRadius.circular(14)),
            child: Text(t['faceNoCam']!, textAlign: TextAlign.center, style: K.cardP.copyWith(color: T.errText)),
          )
        else const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: T.blue)),
        const SizedBox(height: 18),
        if (ready)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_done ? Icons.verified_rounded : _phaseIcon(), color: T.green, size: 26),
            const SizedBox(width: 10),
            Flexible(child: Text(_hint, textAlign: TextAlign.center,
                style: K.cardH.copyWith(fontSize: 22, color: _done ? T.green : T.navy))),
          ]),
        if (ready) ...[
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 4; i++) ...[
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _phase > i || _done ? T.green : (_phase == i ? T.blue : T.line),
                ),
              ),
              if (i < 4) const SizedBox(width: 12),
            ],
          ]),
        ],
        const SizedBox(height: 14),
        KButton(t['cancel']!, variant: 'outline', onTap: () { _cancelled = true; _timer?.cancel(); widget.onCancel(); }),
      ]),
    );
  }

  /// Cho'zilmagan doira preview + qadam ishorasi.
  Widget _circle() {
    final ps = _cam!.value.previewSize;
    final pw = ps?.width ?? 1280.0;
    final ph = ps?.height ?? 720.0;
    return SizedBox(
      width: 340, height: 340,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 340, height: 340,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _stepOk ? T.green : T.blue, width: 6),
          ),
        ),
        ClipOval(
          child: SizedBox(
            width: 322, height: 322,
            child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: pw, height: ph, child: CameraPreview(_cam!))),
          ),
        ),
        if (_stepOk)
          Container(
            width: 322, height: 322, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.25)),
            child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 96),
          ),
      ]),
    );
  }
}
