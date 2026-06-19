import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/tokens.dart';
import 'vk_controller.dart';

/// Bottom on-screen keyboard overlay. Slides up when a KField is focused.
class VkOverlay extends ConsumerWidget {
  const VkOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vk = ref.watch(vkProvider);
    final c = ref.read(vkProvider.notifier);
    return AnimatedSlide(
      offset: vk.visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: T.vkPanel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Fn(label: vk.lang.toUpperCase(), onTap: c.cycleLang),
                  const Text('Klaviatura', style: TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w600)),
                  _Fn(label: '✕', color: T.recRed, onTap: c.hide),
                ],
              ),
              const SizedBox(height: 12),
              // key rows
              for (final row in vkLayouts[vk.lang]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final k in row) _Key(label: vk.shift ? k.toUpperCase() : k, onTap: () => c.key(k)),
                    ],
                  ),
                ),
              // bottom row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Key(label: '⇧', wide: true, active: vk.shift, onTap: c.toggleShift),
                  _Key(label: '␣', space: true, onTap: c.space),
                  _Key(label: '⌫', wide: true, onTap: c.backspace),
                  _Key(label: '⏎', enter: true, onTap: c.enter),
                ],
              ),
            ],
          ),
        ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(color: color ?? T.vkWide, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.wide = false, this.space = false, this.enter = false, this.active = false});
  final String label;
  final VoidCallback onTap;
  final bool wide, space, enter, active;
  @override
  Widget build(BuildContext context) {
    final w = space ? 520.0 : (enter ? 160.0 : (wide ? 140.0 : 86.0));
    final bg = enter ? T.green : (active ? T.blue : (wide ? T.vkWide : T.vkKey));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: 84,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: T.vkKeyShadow, offset: Offset(0, 3))],
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
