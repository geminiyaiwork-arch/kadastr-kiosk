import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/tokens.dart';

/// Kiosk → xodim qo'ng'irog'i (WebRTC caller). Signaling: server rendezvous (long-poll).
/// DIQQAT: flutter_webrtc `libwebrtc.dll` — Smart App Control uni bloklashi mumkin (test).
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.employeeId, required this.name, required this.video, this.onClose});
  final int employeeId;
  final String name;
  final bool video;
  final VoidCallback? onClose; // inline ishlatilганда (Navigator.pop o'rniga)
  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  String? _callId;
  Timer? _poll;
  bool _remoteSet = false;
  String _status = 'ulanmoqda…';
  bool _connected = false;
  bool _ended = false;
  final List<Map<String, dynamic>> _pendCands = []; // call_id kelmaguncha buferlangan ICE nomzodlar
  Timer? _durTimer;
  int _dur = 0; // suhbat davomiyligi (soniya)
  String get _durText { final m = _dur ~/ 60, s = _dur % 60; return '$m:${s.toString().padLeft(2, '0')}'; }

  void _postCand(Map<String, dynamic> cand) {
    ref.read(dioProvider).post('/call/ice', data: {'call_id': _callId, 'side': 'k', 'candidate': cand}).catchError((_) => null);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _local.initialize();
      await _remote.initialize();
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video ? {'facingMode': 'user'} : false,
      });
      _local.srcObject = _stream;
      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          // O'z serverimizdagi TURN (har qanday tarmoqda ovoz/video oqadi)
          {'urls': 'turn:213.230.121.40:3478', 'username': 'kadastr', 'credential': 'KadastrTurn2026uz'},
          {'urls': 'turn:213.230.121.40:3478?transport=tcp', 'username': 'kadastr', 'credential': 'KadastrTurn2026uz'},
        ],
      });
      for (final tr in _stream!.getTracks()) {
        await _pc!.addTrack(tr, _stream!);
      }
      _pc!.onTrack = (e) {
        if (e.streams.isNotEmpty) {
          _remote.srcObject = e.streams[0];
          if (mounted) setState(() { _connected = true; _status = widget.name; });
          _durTimer ??= Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _dur++); }); // vaqt hisoblagich
        }
      };
      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        final cand = {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex};
        if (_callId == null) { _pendCands.add(cand); return; } // call_id kelmagunча bufer (yo'qolmasin)
        _postCand(cand);
      };
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      final r = await ref.read(dioProvider).post('/call/start', data: {
        'to_employee_id': widget.employeeId, 'video': widget.video,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
      final data = Map<String, dynamic>.from(r.data as Map);
      if (data['online'] == false) { _fail('Xodim hozir joyida yo‘q'); return; }
      _callId = data['call_id']?.toString();
      for (final c in _pendCands) { _postCand(c); } // buferdagi nomzodlarni yuborish (host-nomzod yo'qolmaydi)
      _pendCands.clear();
      if (mounted) setState(() => _status = 'Chaqirilyapti…');
      _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _tick());
    } catch (e) {
      _fail('Qo‘ng‘iroq boshlanmadi');
    }
  }

  Future<void> _tick() async {
    if (_callId == null || _ended) return;
    final dio = ref.read(dioProvider);
    try {
      final ar = await dio.post('/call/answer-poll', data: {'call_id': _callId});
      final ad = Map<String, dynamic>.from(ar.data as Map);
      if (ad['state'] == 'ended') { _hangup(); return; }
      if (ad['answer'] != null && !_remoteSet) {
        _remoteSet = true;
        final a = Map<String, dynamic>.from(ad['answer'] as Map);
        await _pc?.setRemoteDescription(RTCSessionDescription(a['sdp'], a['type']));
        if (mounted) setState(() => _status = 'ulanmoqda…');
      }
      final ir = await dio.post('/call/ice-poll', data: {'call_id': _callId, 'side': 'k'});
      final id = Map<String, dynamic>.from(ir.data as Map);
      for (final c in (id['cands'] as List? ?? const [])) {
        final cm = Map<String, dynamic>.from(c as Map);
        await _pc?.addCandidate(RTCIceCandidate(cm['candidate'], cm['sdpMid'], cm['sdpMLineIndex']));
      }
    } catch (_) {}
  }

  void _fail(String msg) {
    if (mounted) setState(() => _status = msg);
    Future.delayed(const Duration(seconds: 2), _close);
  }

  void _hangup() {
    if (_callId != null) ref.read(dioProvider).post('/call/hangup', data: {'call_id': _callId}).catchError((_) => null);
    _close();
  }

  Future<void> _close() async {
    if (_ended) return;
    _ended = true;
    _poll?.cancel();
    _durTimer?.cancel();
    try { for (final t in _stream?.getTracks() ?? const []) { await t.stop(); } } catch (_) {}
    try { await _pc?.close(); } catch (_) {}
    try { await _local.dispose(); } catch (_) {}
    try { await _remote.dispose(); } catch (_) {}
    if (!mounted) return;
    if (widget.onClose != null) { widget.onClose!(); } else { Navigator.of(context).maybePop(); }
  }

  @override
  void dispose() {
    if (!_ended) { _poll?.cancel(); try { _pc?.close(); } catch (_) {} }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1430),
      body: Stack(children: [
        // Remote (to'liq ekran)
        Positioned.fill(
          child: _connected && widget.video
              ? RTCVideoView(_remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.person_rounded, color: Colors.white24, size: 140),
                  const SizedBox(height: 16),
                  Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                ])),
        ),
        // Local PiP
        if (widget.video)
          Positioned(
            right: 20, top: 40, width: 140, height: 200,
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
          ),
        // Yuqori holat — ism + vaqt hisoblagich (Telegram uslubi)
        if (_connected)
          Positioned(top: 44, left: 0, right: 0, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text('🔴 $_durText', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ))),
        // Tugatish
        Positioned(
          left: 0, right: 0, bottom: 50,
          child: Center(child: GestureDetector(
            onTap: _hangup,
            child: Container(
              width: 84, height: 84,
              decoration: const BoxDecoration(color: T.recRed, shape: BoxShape.circle),
              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 40),
            ),
          )),
        ),
      ]),
    );
  }
}
