import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/env.dart';
import '../core/i18n/strings.dart';
import '../core/network/api_client.dart';
import '../core/theme/tokens.dart';
import '../router.dart';
import 'vk_controller.dart';
import 'vk_fields.dart';
import 'vk_settings.dart';

/// Ekran klaviaturasi — SURILADIGAN (istalgan joyga), sozlanadigan (rang/o'lcham/
/// effekt — saqlanadi) va bosganda YONISH effekti bilan. KField fokuslanganda chiqadi.
class VkOverlay extends ConsumerStatefulWidget {
  const VkOverlay({super.key});
  @override
  ConsumerState<VkOverlay> createState() => _VkOverlayState();
}

class _VkOverlayState extends ConsumerState<VkOverlay> {
  Offset? _drag; // sudrash paytidagi lokal joy (tugagach settings'ga saqlanadi)
  bool _settings = false;
  bool _userDismissed = false; // foydalanuvchi ✕ bosса — shu sahifада qayta auto-ochilmaydi
  // QR telefon-pult
  String? _kbToken;
  bool _kbOn = false;
  bool _kbShowQr = false;
  bool _kbConnected = false;

  double _canvasScale() {
    final mq = MediaQuery.of(context).size;
    return math.min(mq.width / Env.canvasW, mq.height / Env.canvasH);
  }

  String _genToken() {
    final r = math.Random.secure();
    return List.generate(20, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  String get _phoneUrl => '${Env.portalOrigin}/kb.html?s=${_kbToken ?? ''}';

  void _toggleKb() {
    if (_kbOn) {
      // allaqachon yoqilgan — QR modalni qayta ko'rsatamiz (ulanishni to'xtatmaymiz)
      setState(() => _kbShowQr = true);
    } else {
      final tok = _genToken();
      setState(() {
        _kbToken = tok;
        _kbOn = true;
        _kbShowQr = true;
        _kbConnected = false;
      });
      _kbLoop(tok);
    }
  }

  // Telefon matnini long-poll bilan olib, kiosk katagiga yozadi (faqat 1 telefon — server qulflaydi).
  Future<void> _kbLoop(String token) async {
    final dio = ref.read(dioProvider);
    while (mounted && _kbOn && _kbToken == token) {
      try {
        final r = await dio.get('/kb/poll',
            queryParameters: {'s': token}, options: Options(receiveTimeout: const Duration(seconds: 30)));
        if (!mounted || _kbToken != token) break;
        final m = Map<String, dynamic>.from(r.data as Map);
        if (m['hello'] == true) {
          _onKbConnect();
        } else if (m['action'] == 'enter') {
          _onKbConnect();
          ref.read(vkProvider.notifier).enter(); // telefon Enter → submit
        } else if (m['action'] == 'tab') {
          _onKbConnect();
          _focusNextField(); // telefon Tab → keyingi input
        } else if (m['text'] != null) {
          _onKbConnect();
          ref.read(vkProvider.notifier).setRemoteText('${m['text']}');
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // Telefon ulanди — ✓ ko'rsatamiz va QR modalни o'zi yopamiz.
  void _onKbConnect() {
    if (!mounted) return;
    if (!_kbConnected || _kbShowQr) setState(() { _kbConnected = true; _kbShowQr = false; });
  }

  // Kiosk boshqa katakка o'tса — telefonдаги matnни tozalash buyrug'i.
  void _sendKbClear() {
    final tok = _kbToken;
    if (tok == null) return;
    ref.read(dioProvider).post('/kb/cmd', data: {'s': tok, 'cmd': 'clear'}).then((_) {}, onError: (_) {});
  }

  // Keyingi inputга o'tish (registry tartibi bo'yicha).
  void _focusNextField() {
    final fields = ref.read(vkFieldsProvider);
    if (fields.isEmpty) return;
    final cur = ref.read(vkProvider).target;
    final idx = fields.indexWhere((e) => e.controller == cur);
    final next = fields[(idx + 1) % fields.length];
    ref.read(vkProvider.notifier).show(next.controller, lang: ref.read(localeProvider), onEnter: next.onEnter);
  }

  // Foydalanuvchi ✕ bosди — yashiramiz va shu sahifада auto-ochilmaydi.
  void _dismiss() {
    _userDismissed = true;
    ref.read(vkProvider.notifier).hide();
  }

  @override
  void dispose() {
    _kbOn = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vk = ref.watch(vkProvider);
    final c = ref.read(vkProvider.notifier);
    final s = ref.watch(vkSettingsProvider);
    // Boshqa katakка o'tса → telefon-pult matnini tozalash; "standart"да drag'ni tiklash (pastga)
    ref.listen<VkState>(vkProvider, (prev, next) {
      if (prev?.target != next.target && _kbOn && _kbToken != null && next.target != null) _sendKbClear();
    });
    ref.listen<VkSettings>(vkSettingsProvider, (prev, next) {
      if (next.pos == null && _drag != null && mounted) setState(() => _drag = null);
    });
    // BOSHQA sahifага o'tса — klaviatura darhol yo'qolsin (yangi sahifада input bo'lsa qayta ochiladi)
    ref.listen<String>(currentRouteProvider, (prev, next) {
      if (prev != next) {
        _userDismissed = false;
        if (ref.read(vkProvider).visible) ref.read(vkProvider.notifier).hide();
      }
    });
    // AUTO ochilish/yopilish: sahifада input bor bo'lsa klaviatura o'zi ochiladi;
    // input yo'q (bosh sahifа/orqа) bo'lsa o'zi yopiladi.
    ref.listen<List<VkFieldReg>>(vkFieldsProvider, (prev, next) {
      if (next.isEmpty) {
        _userDismissed = false;
        if (ref.read(vkProvider).visible) ref.read(vkProvider.notifier).hide();
      } else if ((prev == null || prev.isEmpty) && !_userDismissed && !ref.read(vkProvider).visible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _userDismissed) return;
          final f = ref.read(vkFieldsProvider);
          if (f.isNotEmpty && !ref.read(vkProvider).visible) {
            ref.read(vkProvider.notifier).show(f.first.controller, lang: ref.read(localeProvider), onEnter: f.first.onEnter);
          }
        });
      }
    });

    if (!vk.visible) return const SizedBox.shrink();

    final panelW = (972.0 * s.scale).clamp(600.0, 1060.0);
    final defLeft = (Env.canvasW - panelW) / 2;
    final estH = 90 + 460 * ((panelW - 32) / 1034) + 40; // taxminiy balandlik (default/drag)
    final custom = _drag ?? s.pos;
    final left = (custom?.dx ?? defLeft).clamp(0.0, Env.canvasW - panelW);

    final kbCard = Material(
      type: MaterialType.transparency,
      child: Container(
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 10))],
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // === Sudrash tutqichi + boshqaruv ===
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  final cs = _canvasScale();
                  final dd = cs > 0 ? d.delta / cs : d.delta;
                  final cur = _drag ?? s.pos ?? Offset(defLeft, Env.canvasH - 24 - estH);
                  setState(() => _drag = Offset(cur.dx + dd.dx, cur.dy + dd.dy));
                },
                onPanEnd: (_) {
                  if (_drag != null) ref.read(vkSettingsProvider.notifier).setPos(_drag!);
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 2),
                  child: Row(
                    children: [
                      _Fn(label: vk.lang.toUpperCase(), onTap: c.cycleLang),
                      const SizedBox(width: 8),
                      _Fn(label: '⚙️', onTap: () => setState(() => _settings = !_settings)),
                      const SizedBox(width: 8),
                      _Fn(label: !_kbOn ? '📱 Ulanish' : (_kbConnected ? '📱 ✓' : '📱 QR'),
                          color: !_kbOn ? T.vkWide : (_kbConnected ? T.green : T.blue), onTap: _toggleKb),
                      Expanded(
                        child: Center(
                          child: Icon(Icons.drag_handle_rounded, color: s.text.withOpacity(0.55), size: 34),
                        ),
                      ),
                      _Fn(label: '📋', color: T.blue, onTap: c.paste),
                      const SizedBox(width: 8),
                      _Fn(label: '✕', color: T.recRed, onTap: _dismiss),
                    ],
                  ),
                ),
              ),
              // === Sozlamalar paneli (ochilsa) ===
              if (_settings) _SettingsPanel(s: s),
              // === Tugmalar (panelga sig'ish uchun FittedBox) ===
              SizedBox(
                width: panelW - 32,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final row in vkLayouts[vk.lang]!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final k in row)
                                _Key(label: vk.shift ? k.toUpperCase() : k, bg: s.key, fg: s.text, glow: s.glow, onTap: () => c.key(k)),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Key(label: '⇧', bg: s.key, fg: s.text, glow: s.glow, wide: true, active: vk.shift, onTap: c.toggleShift),
                          _Key(label: '␣', bg: s.key, fg: s.text, glow: s.glow, space: true, onTap: c.space),
                          _Key(label: '⌫', bg: s.key, fg: s.text, glow: s.glow, wide: true, onTap: c.backspace),
                          _Key(label: '⏎', bg: s.key, fg: s.text, glow: s.glow, enter: true, onTap: c.enter),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

    final kb = (custom == null)
        ? Positioned(left: left, bottom: 24, width: panelW, child: kbCard) // default: pastda
        : Positioned(left: left, top: custom.dy.clamp(0.0, Env.canvasH - 120), width: panelW, child: kbCard);
    return Positioned.fill(
      child: Stack(children: [
        kb,
        if (_kbShowQr && _kbToken != null) Positioned.fill(child: _qrModal(s)),
      ]),
    );
  }

  // QR MODAL — qorong'i fon + markazда QR karta (ulanганда o'zi yopiladi).
  Widget _qrModal(VkSettings s) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _kbShowQr = false),
      child: Container(
        color: const Color(0xCC000000),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {}, // karta ustiga bosса yopilmasin
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Telefondan yozish', style: TextStyle(color: T.navy, fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Telefon kamerangiz bilan QR-kodni skanerlang.\nFaqat 1 telefon ulanadi.',
                  textAlign: TextAlign.center, style: TextStyle(color: T.muted, fontSize: 18, height: 1.35)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: T.line, width: 2), borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: _phoneUrl, size: 300, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => setState(() => _kbShowQr = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
                  decoration: BoxDecoration(color: T.vkPanel, borderRadius: BorderRadius.circular(14)),
                  child: const Text('Yopish', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sozlamalar paneli — rang/o'lcham/effekt (darhol saqlanadi).
class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel({required this.s});
  final VkSettings s;

  static const _panelColors = [T.vkPanel, Color(0xFF10162B), Color(0xFF0E2E22), Color(0xFF241B3D), Color(0xFF102A4C)];
  static const _keyColors = [T.vkKey, Color(0xFF2A2F45), Color(0xFF1FA463), Color(0xFF2F6FE3), Color(0xFF7A3FB0), Color(0xFFB05B2E)];
  static const _textColors = [Colors.white, Colors.black, Color(0xFFFFD54F)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(vkSettingsProvider.notifier);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Panel rangi', [for (final c in _panelColors) _swatch(c, s.panel == c, () => n.setPanel(c))]),
          const SizedBox(height: 8),
          _row('Tugma rangi', [for (final c in _keyColors) _swatch(c, s.key == c, () => n.setKey(c))]),
          const SizedBox(height: 8),
          _row('Matn rangi', [for (final c in _textColors) _swatch(c, s.text == c, () => n.setText(c))]),
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 130, child: Text('O‘lcham', style: TextStyle(color: Colors.white70, fontSize: 18))),
            _mini('−', () => n.setScale(s.scale - 0.1)),
            SizedBox(width: 70, child: Center(child: Text('${(s.scale * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)))),
            _mini('+', () => n.setScale(s.scale + 0.1)),
            const SizedBox(width: 20),
            const SizedBox(width: 120, child: Text('Bosish effekti', style: TextStyle(color: Colors.white70, fontSize: 18))),
            GestureDetector(
              onTap: n.toggleGlow,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(color: s.glow ? T.green : T.vkWide, borderRadius: BorderRadius.circular(10)),
                child: Text(s.glow ? 'YONIQ' : 'O‘CHIQ', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const Spacer(),
            _mini('⟳ joy', n.resetPos, w: 90),
            const SizedBox(width: 8),
            _mini('standart', n.reset, w: 110),
          ]),
        ],
      ),
    );
  }

  Widget _row(String label, List<Widget> swatches) => Row(children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 18))),
        ...swatches,
      ]);

  Widget _swatch(Color c, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: sel ? Colors.white : const Color(0x33FFFFFF), width: sel ? 3 : 1),
          ),
        ),
      );

  Widget _mini(String label, VoidCallback onTap, {double w = 54}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: w,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: T.vkWide, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}

class _Fn extends StatelessWidget {
  const _Fn({required this.label, required this.onTap, this.color});
  final String label;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(color: color ?? T.vkWide, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Tugma — bosilganda YONISH (glow + scale) effekti bilan.
class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.bg,
    required this.fg,
    required this.glow,
    this.wide = false,
    this.space = false,
    this.enter = false,
    this.active = false,
  });
  final String label;
  final VoidCallback onTap;
  final Color bg, fg;
  final bool glow, wide, space, enter, active;
  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.space ? 520.0 : (widget.enter ? 160.0 : (widget.wide ? 140.0 : 86.0));
    final base = widget.enter ? T.green : (widget.active ? T.blue : (widget.wide ? T.vkWide : widget.bg));
    final lit = _down && widget.glow;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: lit ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: w,
          height: 84,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lit ? Color.lerp(base, Colors.white, 0.35) : base,
            borderRadius: BorderRadius.circular(14),
            boxShadow: lit
                ? [BoxShadow(color: base.withOpacity(0.9), blurRadius: 22, spreadRadius: 2)]
                : const [BoxShadow(color: T.vkKeyShadow, offset: Offset(0, 3))],
          ),
          child: Text(widget.label, style: TextStyle(color: widget.fg, fontSize: 32, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
