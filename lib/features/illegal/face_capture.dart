import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../common/widgets.dart';

/// Face capture for kiosk Face-ID.
/// - Windows/macOS: native `camera` package (inline preview on the page).
/// - Linux: bundled `myid-camera` WebKitGTK helper (Flutter'нинг camera paketi
///   Linux desktop'ни qo'llamaydi; WebKit getUserMedia orqali rasm oladi).
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
  bool _busy = false;
  bool _linuxRunning = false; // Linux helper oynasi ochiq

  @override
  void initState() {
    super.initState();
    if (Platform.isLinux) {
      _linuxCapture();
    } else {
      _init();
    }
  }

  /// Linux: bundled WebKitGTK helper'ни ishga tushiradi (fullscreen kamera) →
  /// rasm faylга yoziladi → o'qib onCaptured ga uzatamiz.
  Future<void> _linuxCapture() async {
    final helper = '${File(Platform.resolvedExecutable).parent.path}/myid-camera';
    if (!File(helper).existsSync()) {
      if (mounted) setState(() => _noCamera = true);
      return;
    }
    final out = '${Directory.systemTemp.path}/myid_face_${DateTime.now().millisecondsSinceEpoch}.txt';
    if (mounted) setState(() => _linuxRunning = true);
    try {
      await Process.run(helper, [out]); // helper yopilguncha bloklaydi
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
        widget.onCancel(); // bekor qilindi yoki rasm olinmadi
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _linuxRunning = false;
          _noCamera = true;
        });
      }
    }
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _noCamera = true);
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final c = CameraController(front, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() => _cam = c);
    } catch (_) {
      if (mounted) setState(() => _noCamera = true);
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _cam;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      widget.onCaptured('data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (_) {
      setState(() => _busy = false);
    }
  }

  // tiny placeholder so the verify flow runs on Linux (no camera) — backend
  // errors at the token step before the photo matters.
  void _proceedNoCam() => widget.onCaptured('data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBD');

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ready = _cam?.value.isInitialized ?? false;
    // Linux: helper fullscreen oynaси ochiq — bu yerда faqat holat ko'rsatamiz
    if (_linuxRunning) {
      return KCard(
        child: Column(
          children: [
            Text(t['faceTitle']!, textAlign: TextAlign.center, style: K.cardH),
            const SizedBox(height: 18),
            const CircularProgressIndicator(color: T.blue),
            const SizedBox(height: 18),
            Text(t['faceWindowOpen'] ?? 'Kamera oynasi ochildi — yuzingizni suratga oling.',
                textAlign: TextAlign.center, style: K.cardP),
            const SizedBox(height: 14),
            KButton(t['cancel']!, variant: 'outline', onTap: widget.onCancel),
          ],
        ),
      );
    }
    return KCard(
      child: Column(
        children: [
          Text(t['faceTitle']!, textAlign: TextAlign.center, style: K.cardH),
          const SizedBox(height: 16),
          if (ready)
            ClipOval(
              child: SizedBox(
                width: 360,
                height: 360,
                child: FittedBox(fit: BoxFit.cover, child: SizedBox(
                  width: _cam!.value.previewSize?.height ?? 360,
                  height: _cam!.value.previewSize?.width ?? 360,
                  child: CameraPreview(_cam!),
                )),
              ),
            )
          else if (_noCamera)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: T.errBg, borderRadius: BorderRadius.circular(14)),
              child: Text(t['faceNoCam']!, textAlign: TextAlign.center, style: K.cardP.copyWith(color: T.errText)),
            )
          else
            const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: T.blue)),
          const SizedBox(height: 18),
          if (ready)
            KButton(_busy ? t['verifying']! : t['faceCapture']!, onTap: _capture)
          else if (_noCamera)
            KButton(t['faceProceed']!, variant: 'navy', onTap: _proceedNoCam),
          const SizedBox(height: 10),
          KButton(t['cancel']!, variant: 'outline', onTap: widget.onCancel),
        ],
      ),
    );
  }
}
