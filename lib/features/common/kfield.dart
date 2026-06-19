import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/tokens.dart';
import '../../shell/vk_controller.dart';

/// Styled text field that drives the custom on-screen keyboard (readOnly so the
/// native IME never pops; edited via VkOverlay). Web .f-input / .f-label.
class KField extends ConsumerWidget {
  const KField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.onEnter,
    this.lines = 1,
  });
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final VoidCallback? onEnter;
  final int lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: K.fLabel),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          readOnly: true,
          showCursor: true,
          maxLines: lines,
          style: K.fInput,
          cursorColor: T.blue,
          onTap: () => ref.read(vkProvider.notifier).show(controller, lang: lang, onEnter: onEnter),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: K.fInput.copyWith(color: T.muted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(T.rInput),
              borderSide: const BorderSide(color: T.line, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(T.rInput),
              borderSide: const BorderSide(color: T.blue, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
