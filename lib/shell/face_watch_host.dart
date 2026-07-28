import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/strings.dart';
import '../core/network/api_client.dart';
import '../features/ai/voice_controller.dart';
import '../router.dart';

/// FON YUZ-TANISH (1.9.36): bosh sahifa/zastavkada kamera ~4 soniyada bir kadr olib
/// serverga yuboradi ("kamera doim fonda ishlab tursin tanish uchun" — user talabi);
/// "meni eslab qol" bilan ro'yxatdan o'tgan odam tanilsa — ISMI bilan salomlaydi.
/// MAXFIYLIK: fon-kadrlar serverда SAQLANMAYDI (faqat solishtiriladi). Kamera boshqa
/// oqimlar (murojaat-video, hujjat-surat, ro'yxat) ishlaganда DARHOL bo'shatiladi.
class FaceWatchHost extends ConsumerStatefulWidget {
  const FaceWatchHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<FaceWatchHost> createState() => _FaceWatchHostState();
}

class _FaceWatchHostState extends ConsumerState<FaceWatchHost> {
  CameraController? _cam;
  Timer? _t;
  bool _busy = false;
  final Map<String, DateTime> _greeted = {}; // ism -> oxirgi salom (10 daq takrorlamaydi)
  DateTime _lastAny = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
  }

  @override
  void dispose() {
    _t?.cancel();
    _dropCam();
    super.dispose();
  }

  /// Fon-tanish faqat XAVFSIZ paytda: bosh sahifa yoki zastavka, kiosk band emas.
  /// (Boshqa sahifalarda kamera murojaat/hujjat/ro'yxat oqimlariga kerak bo'ladi.)
  bool get _allowed {
    try {
      if (ref.read(kioskBusyProvider) > 0) return false;
      final route = ref.read(currentRouteProvider);
      return ref.read(attractProvider) || route == '/';
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureCam() async {
    if (_cam != null && _cam!.value.isInitialized) return;
    final cams = await availableCameras();
    if (cams.isEmpty) throw 'no-cam';
    final c = CameraController(cams.first, ResolutionPreset.medium, enableAudio: false);
    await c.initialize();
    _cam = c;
  }

  Future<void> _dropCam() async {
    final c = _cam;
    _cam = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (_busy) return;
    if (!_allowed) {
      if (_cam != null) await _dropCam(); // kamerani boshqa oqimlarga bo'shatamiz
      return;
    }
    _busy = true;
    try {
      await _ensureCam();
      final x = await _cam!.takePicture();
      final bytes = await x.readAsBytes();
      if (bytes.length < 4000) return;
      final r = await ref
          .read(dioProvider)
          .post('/face/recognize', data: {'image': base64Encode(bytes)});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['match'] != true) return;
      final name = (m['name'] ?? '').toString().trim();
      if (name.isEmpty) return;
      final now = DateTime.now();
      final last = _greeted[name];
      if (last != null && now.difference(last).inMinutes < 10) return; // takror salom yo'q
      if (now.difference(_lastAny).inSeconds < 25) return;
      final v = ref.read(voiceProvider);
      if (v.speaking || v.recording || v.phase == VoicePhase.thinking) return; // gap bo'linmasin
      _greeted[name] = now;
      _lastAny = now;
      final lang = ref.read(localeProvider);
      final g = {
        'uz': 'Assalomu alaykum, $name! Sizni yana ko‘rganimdan xursandman. Savolingiz bo‘lsa, bemalol ayting.',
        'ru': 'Здравствуйте, $name! Рад снова вас видеть. Если есть вопрос — спрашивайте.',
        'en': 'Hello, $name! Nice to see you again. Feel free to ask me anything.',
      }[lang]!;
      unawaited(ref.read(voiceProvider.notifier).speakText(g));
    } catch (_) {
      await _dropCam(); // kamera band/xato — keyingi urinishда qayta ochiladi
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
