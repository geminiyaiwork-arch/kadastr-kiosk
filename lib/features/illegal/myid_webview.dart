import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';

/// MyID **Web SDK** kamera-yuz oynasi (WebView2, faqat Windows).
///
/// [webUrl] — MyID web sahifasi (`https://web.devmyid.uz/?session_id=...`) — u
/// kiosk kamerasini ochib foydalanuvchi yuzini davlat bazasi bilan solishtiradi.
/// Tasdiqdan keyin MyID `redirect_uri` (= [completeMarker]) ga yo'naltiradi —
/// shuni sezganda [onDone] chaqiriladi (parent oynani yopib backend'ni polllaydi).
class MyIdWebView extends StatefulWidget {
  const MyIdWebView({
    super.key,
    required this.webUrl,
    required this.completeMarker,
    required this.title,
    required this.onDone,
    required this.onCancel,
  });

  final String webUrl;
  final String completeMarker; // redirect_uri (yetganda tasdiq tugadi)
  final String title;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  State<MyIdWebView> createState() => _MyIdWebViewState();
}

class _MyIdWebViewState extends State<MyIdWebView> {
  final _c = WebviewController();
  StreamSubscription<String>? _sub;
  bool _ready = false;
  bool _fired = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _init();
    } else {
      _err = 'unsupported';
    }
  }

  Future<void> _init() async {
    try {
      await _c.initialize();
      await _c.setBackgroundColor(Colors.white);
      await _c.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _sub = _c.url.listen((u) {
        if (!_fired && u.contains(widget.completeMarker)) {
          _fired = true;
          widget.onDone();
        }
      });
      await _c.loadUrl(widget.webUrl);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: T.bg,
      child: Column(
        children: [
          // header: orqaga + sarlavha
          Container(
            height: 130,
            padding: const EdgeInsets.symmetric(horizontal: 36),
            decoration: const BoxDecoration(gradient: T.gNavyH),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCancel,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Text('‹', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: K.pgTitle.copyWith(color: Colors.white)),
                      const SizedBox(height: 2),
                      const Text('MyID — yuzni kamera orqali tasdiqlang', style: TextStyle(fontSize: 19, color: Color(0xCCFFFFFF))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_err == 'unsupported') {
      return _msg('Kamera-yuz tasdiqlash faqat Windows kioskида ishlaydi.\n'
          'Windows mashinada WebView2 + kamera orqali MyID yuzni tekshiradi.');
    }
    if (_err != null) {
      return _msg('WebView xatosi:\n$_err\n\nWindows kioskда WebView2 runtime o‘rnatilganiga ishonch hosil qiling.');
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(color: T.blue));
    }
    return Webview(
      _c,
      permissionRequested: (url, kind, isUserInitiated) async =>
          WebviewPermissionDecision.allow, // kamera/mikrofon — avtomatik ruxsat
    );
  }

  Widget _msg(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 90, color: T.muted),
              const SizedBox(height: 24),
              Text(text, textAlign: TextAlign.center, style: K.cardP),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                  decoration: BoxDecoration(color: T.navy, borderRadius: BorderRadius.circular(16)),
                  child: const Text('Orqaga', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
}
