import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';

/// White rounded card with the standard kiosk border + shadow.
class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(28), this.accent});
  final Widget child;
  final EdgeInsets padding;
  final Color? accent; // optional left border (e.g. result cards)
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: accent != null
            ? Border(left: BorderSide(color: accent!, width: 6), top: const BorderSide(color: T.line, width: 1.5), right: const BorderSide(color: T.line, width: 1.5), bottom: const BorderSide(color: T.line, width: 1.5))
            : Border.all(color: T.line, width: 1.5),
        borderRadius: BorderRadius.circular(T.rCard),
        boxShadow: T.shadow,
      ),
      child: child,
    );
  }
}

/// Full-width press-animated button. variant: primary|green|navy|outline.
class KButton extends StatefulWidget {
  const KButton(this.label, {super.key, required this.onTap, this.variant = 'green', this.expand = true});
  final String label;
  final VoidCallback onTap;
  final String variant;
  final bool expand;
  @override
  State<KButton> createState() => _KButtonState();
}

class _KButtonState extends State<KButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final outline = widget.variant == 'outline';
    final bg = switch (widget.variant) {
      'primary' => T.blue,
      'navy' => T.navy,
      'outline' => Colors.white,
      _ => T.green,
    };
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 30),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: outline ? Border.all(color: T.line, width: 2) : null,
            borderRadius: BorderRadius.circular(T.rBtn),
          ),
          child: Text(widget.label, textAlign: TextAlign.center,
              style: K.btn.copyWith(color: outline ? T.navy : Colors.white)),
        ),
      ),
    );
  }
}

/// Key→value rows inside a result card (web .res .kv).
class KvRows extends StatelessWidget {
  const KvRows(this.rows, {super.key});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    return Column(
      children: [
        for (var i = 0; i < visible.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: i == visible.length - 1 ? null : const Border(bottom: BorderSide(color: T.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: Text(visible[i].$1, style: K.kv.copyWith(color: T.muted))),
                const SizedBox(width: 16),
                Expanded(child: Text(visible[i].$2, textAlign: TextAlign.right, style: K.kv.copyWith(fontWeight: FontWeight.w700))),
              ],
            ),
          ),
      ],
    );
  }
}

/// Async view helper: spinner / error / data.
class AsyncView<V> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.data, this.onError});
  final AsyncValue<V> value;
  final Widget Function(V) data;
  final String? onError;
  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: T.blue)),
      ),
      error: (e, _) => KCard(child: Text(onError ?? 'Ma’lumotni yuklab bo‘lmadi', style: K.cardP)),
    );
  }
}
