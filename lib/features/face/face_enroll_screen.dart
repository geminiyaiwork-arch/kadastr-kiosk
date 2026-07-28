import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../../core/i18n/strings.dart';
import '../../core/network/api_client.dart';
import '../../router.dart';
import '../ai/voice_controller.dart';

/// "MENI ESLAB QOL" (1.9.36): "Kadastr AI, meni eslab qol" deyilganda ochiladi.
/// Oqim: kamera → 3-2-1 avto-surat → "Ismingiz nima?" (ovozda so'raydi, STT bilan
/// yozib oladi) → tasdiqlash (ism tahrirlanadi) → serverga saqlash. Keyingi safar
/// fon-kamera tanib, ISMI bilan salomlaydi. Rasm+ism FAQAT shu ixtiyoriy oqimda
/// saqlanadi (fon-kadrlar saqlanmaydi).
class FaceEnrollScreen extends ConsumerStatefulWidget {
  const FaceEnrollScreen({super.key});
  @override
  ConsumerState<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

enum _St { init, countdown, asking, listening, confirm, saving, done, error }

class _FaceEnrollScreenState extends ConsumerState<FaceEnrollScreen> {
  static const _bgTop = Color(0xFF10266B);
  static const _bgBot = Color(0xFF061233);
  static const _indigo = Color(0xFF5457F5);

  CameraController? _cam;
  _St _st = _St.init;
  int _count = 3;
  Uint8List? _photo;
  final _nameCtrl = TextEditingController();
  final _rec = AudioRecorder();
  String _err = '';
  bool _closing = false;

  Map<String, dynamic> get _t => I18N[ref.read(localeProvider)]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kioskBusyProvider.notifier).state++; // idle-reset urmasin
      _start();
    });
  }

  @override
  void dispose() {
    try {
      ref.read(kioskBusyProvider.notifier).state--;
    } catch (_) {}
    _cam?.dispose();
    _rec.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _st = _St.init;
      _count = 3;
      _photo = null;
    });
    try {
      if (_cam == null || !_cam!.value.isInitialized) {
        final cams = await availableCameras();
        if (cams.isEmpty) throw 'no-cam';
        final c = CameraController(cams.first, ResolutionPreset.high, enableAudio: false);
        await c.initialize();
        if (!mounted) {
          await c.dispose();
          return;
        }
        _cam = c;
      }
      setState(() => _st = _St.countdown);
      unawaited(ref.read(voiceProvider.notifier).speakText(_t['feLook']));
      while (_count > 0 && mounted && _st == _St.countdown) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted || _st != _St.countdown) return;
        setState(() => _count--);
      }
      if (!mounted || _st != _St.countdown) return;
      final x = await _cam!.takePicture();
      _photo = await x.readAsBytes();
      if (!mounted) return;
      await _askName();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _st = _St.error;
        _err = _t['feNoCam'];
      });
    }
  }

  Future<void> _askName() async {
    setState(() => _st = _St.asking);
    await ref.read(voiceProvider.notifier).speakText(_t['feAskName']);
    if (!mounted) return;
    setState(() => _st = _St.listening);
    try {
      final path = '${Directory.systemTemp.path}/kadastr_name.wav';
      await _rec.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: path);
      await Future.delayed(const Duration(milliseconds: 4500));
      try {
        await _rec.stop();
      } catch (_) {}
      var name = '';
      final f = File(path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (bytes.length > 4000) {
          final r = await ref.read(dioProvider).post('/stt',
              queryParameters: {'lang': ref.read(localeProvider)},
              data: Stream.fromIterable([bytes]),
              options: Options(
                  contentType: 'application/octet-stream',
                  headers: {Headers.contentLengthHeader: bytes.length}));
          name = ((Map<String, dynamic>.from(r.data as Map))['text'] ?? '').toString().trim();
        }
      }
      name = name.replaceAll(RegExp(r'[.,!?«»"]'), '').trim();
      final ws = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (ws.length > 3) name = ws.take(3).join(' ');
      _nameCtrl.text = name;
    } catch (_) {
      _nameCtrl.text = '';
    }
    if (mounted) setState(() => _st = _St.confirm);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2 || _photo == null) return;
    setState(() => _st = _St.saving);
    try {
      final r = await ref
          .read(dioProvider)
          .post('/face/enroll', data: {'image': base64Encode(_photo!), 'name': name});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['ok'] == true) {
        setState(() => _st = _St.done);
        final msg = (_t['feSaved'] as String).replaceAll('{name}', name);
        await ref.read(voiceProvider.notifier).speakText(msg);
        if (mounted && !_closing) {
          _closing = true;
          context.go('/');
        }
      } else {
        final noFace = '${m['error'] ?? ''}'.contains('no face');
        setState(() {
          _st = _St.error;
          _err = noFace ? _t['feNoFace'] : _t['feFail'];
        });
        unawaited(ref.read(voiceProvider.notifier).speakText(_err));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _st = _St.error;
        _err = _t['feFail'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final showPreview = _st == _St.init || _st == _St.countdown;
    final ps = _cam?.value.previewSize;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bgTop, _bgBot]),
      ),
      child: Stack(children: [
        Column(children: [
          const SizedBox(height: 120),
          Text(t['feTitle'],
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 60),
          // Doira: kamera preview / olingan surat
          SizedBox(
            width: 640,
            height: 640,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 640,
                height: 640,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _st == _St.listening ? _indigo : Colors.white24, width: 6),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40)],
                ),
                clipBehavior: Clip.antiAlias,
                child: showPreview && _cam != null && _cam!.value.isInitialized
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: ps?.width ?? 1280,
                          height: ps?.height ?? 720,
                          child: CameraPreview(_cam!),
                        ),
                      )
                    : (_photo != null
                        ? Image.memory(_photo!, fit: BoxFit.cover)
                        : const ColoredBox(color: Color(0xFF13204A))),
              ),
              if (_st == _St.countdown && _count > 0)
                Text('$_count',
                    style: const TextStyle(
                        fontSize: 200,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 30)])),
              if (_st == _St.saving || _st == _St.init)
                const SizedBox(width: 90, height: 90, child: CircularProgressIndicator(strokeWidth: 6, color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 46),
          // Holat matni / ism tasdiqlash
          if (_st == _St.countdown || _st == _St.init)
            Text(t['feLook'],
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Colors.white70)),
          if (_st == _St.asking || _st == _St.listening)
            Text(_st == _St.listening ? '🎤 ${t['feListening']}' : t['feAskName'],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white)),
          if (_st == _St.confirm || _st == _St.saving) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 140),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: _nameCtrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, color: Color(0xFF10266B)),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: t['feName'],
                    contentPadding: const EdgeInsets.symmetric(vertical: 26),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 34),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _btn(t['feSave'], const Color(0xFF1FA463), _st == _St.saving ? null : _save),
              const SizedBox(width: 24),
              _btn(t['feResay'], _indigo, _st == _St.saving ? null : _askName),
              const SizedBox(width: 24),
              _btn(t['feRetake'], const Color(0xFF41508A), _st == _St.saving ? null : _start),
            ]),
          ],
          if (_st == _St.error) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: Text(_err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Color(0xFFFFB4B4))),
            ),
            const SizedBox(height: 30),
            _btn(t['feRetry'], _indigo, _start),
          ],
        ]),
        // Orqaga
        Positioned(
          left: 36,
          top: 40,
          child: GestureDetector(
            onTap: () => context.go('/'),
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [BoxShadow(color: Color(0x3D000000), offset: Offset(0, 6), blurRadius: 18)],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF16224A), size: 36),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _btn(String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 22),
        decoration: BoxDecoration(
          color: onTap == null ? color.withOpacity(0.4) : color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}
