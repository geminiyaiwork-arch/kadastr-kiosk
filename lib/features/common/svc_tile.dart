import 'package:flutter/material.dart';

import '../../core/theme/icons.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';

/// Service grid tile — green / blue / accent (navy gradient) variants.
class SvcTile extends StatefulWidget {
  const SvcTile({super.key, required this.icon, required this.label, required this.variant, required this.onTap});
  final String icon;
  final String label;
  final String variant; // green | blue | accent
  final VoidCallback onTap;

  @override
  State<SvcTile> createState() => _SvcTileState();
}

class _SvcTileState extends State<SvcTile> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final accent = widget.variant == 'accent';
    final stroke = accent
        ? Colors.white
        : (widget.variant == 'green' ? T.green : T.blue);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          constraints: const BoxConstraints(minHeight: 212),
          decoration: BoxDecoration(
            gradient: accent ? T.gNavyH : null,
            color: accent ? null : Colors.white,
            border: Border.all(color: accent ? T.navy : T.line, width: 1.5),
            borderRadius: BorderRadius.circular(T.rCard),
            boxShadow: T.shadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              kIcon(widget.icon, size: 74, color: stroke),
              const SizedBox(height: 18),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: K.svcLabel.copyWith(color: accent ? Colors.white : T.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
