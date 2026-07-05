import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../core/theme/tokens.dart';
import 'vk_controller.dart';
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

  double _canvasScale() {
    final mq = MediaQuery.of(context).size;
    return math.min(mq.width / Env.canvasW, mq.height / Env.canvasH);
  }

  @override
  Widget build(BuildContext context) {
    final vk = ref.watch(vkProvider);
    final c = ref.read(vkProvider.notifier);
    final s = ref.watch(vkSettingsProvider);
    if (!vk.visible) return const SizedBox.shrink();

    final panelW = (972.0 * s.scale).clamp(600.0, 1060.0);
    final defLeft = (Env.canvasW - panelW) / 2;
    final left = _drag?.dx ?? s.pos?.dx ?? defLeft;
    final top = _drag?.dy ?? s.pos?.dy ?? 1180.0;

    return Positioned(
      left: left.clamp(0.0, Env.canvasW - panelW),
      top: top.clamp(0.0, Env.canvasH - 120),
      width: panelW,
      child: Material(
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
                  final cur = _drag ?? s.pos ?? Offset(defLeft, 1180.0);
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
                      Expanded(
                        child: Center(
                          child: Icon(Icons.drag_handle_rounded, color: s.text.withOpacity(0.55), size: 34),
                        ),
                      ),
                      _Fn(label: '📋', color: T.blue, onTap: c.paste),
                      const SizedBox(width: 8),
                      _Fn(label: '✕', color: T.recRed, onTap: c.hide),
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
