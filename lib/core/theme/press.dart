import 'package:flutter/widgets.dart';

/// Tap target with a press-down scale (web :active transform:scale).
class Press extends StatefulWidget {
  const Press({super.key, required this.child, required this.onTap, this.scale = 0.96});
  final Widget child;
  final VoidCallback onTap;
  final double scale;
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}
