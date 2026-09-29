import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// ALOMAT wake-word sidecar ko'prigi (1.9.53). Kiosk papkasidagi `wake/alomat_wake.exe`
/// (openWakeWord ONNX, mikrofonni o'zi tinglaydi) ishga tushiriladi va ws://127.0.0.1:8765
/// orqali {"event":"wake","score":0.9} kelganda [onWake] chaqiriladi (~0.3 s, serversiz).
/// Exe yo'q bo'lsa (Linux/eski o'rnatma) — jim o'tadi, eski STT-wake ishlayveradi.
class WakeBridge {
  WakeBridge({this.port = 8765, this.threshold = 0.7});
  final int port;
  final double threshold;
  Process? _proc;
  WebSocket? _ws;
  bool _on = false;
  void Function(double score)? onWake;
  void Function(String msg)? log;

  static String? sidecarPath() {
    if (!Platform.isWindows) return null;
    final dir = File(Platform.resolvedExecutable).parent.path;
    final p = '$dir${Platform.pathSeparator}wake${Platform.pathSeparator}alomat_wake.exe';
    return File(p).existsSync() ? p : null;
  }

  Future<void> start() async {
    if (_on) return;
    _on = true;
    final exe = sidecarPath();
    if (exe != null) {
      try {
        final model = '${File(exe).parent.path}${Platform.pathSeparator}alomat.onnx';
        _proc = await Process.start(exe, ['--model', model, '--threshold', '$threshold', '--port', '$port'],
            workingDirectory: File(exe).parent.path, mode: ProcessStartMode.detachedWithStdio);
        log?.call('sidecar started pid=${_proc!.pid}');
      } catch (e) {
        log?.call('sidecar start failed: $e');
      }
    } else {
      log?.call('sidecar exe not found — STT wake only');
    }
    unawaited(_connectLoop());
  }

  Future<void> _connectLoop() async {
    var delay = 1;
    while (_on) {
      try {
        final ws = await WebSocket.connect('ws://127.0.0.1:$port').timeout(const Duration(seconds: 4));
        _ws = ws;
        delay = 1;
        log?.call('sidecar ws connected');
        await for (final m in ws) {
          if (!_on) break;
          try {
            final j = jsonDecode(m as String) as Map<String, dynamic>;
            if (j['event'] == 'wake') onWake?.call((j['score'] as num?)?.toDouble() ?? 1.0);
          } catch (_) {}
        }
      } catch (_) {}
      _ws = null;
      if (!_on) break;
      await Future<void>.delayed(Duration(seconds: delay));
      if (delay < 15) delay *= 2;
    }
  }

  Future<void> stop() async {
    _on = false;
    try { await _ws?.close(); } catch (_) {}
    _ws = null;
    try { _proc?.kill(); } catch (_) {}
    _proc = null;
  }
}
