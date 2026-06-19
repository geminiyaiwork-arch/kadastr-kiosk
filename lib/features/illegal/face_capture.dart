import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../common/widgets.dart';

/// Face capture for kiosk Face-ID (Windows). On Linux/no-camera it shows a
/// fallback so the verify flow (and any MyID error) can still be exercised.
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

  @override
  void initState() {
    super.initState();
    _init();
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
