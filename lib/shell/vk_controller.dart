import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On-screen keyboard layouts (1:1 with app.js VK_LAYOUTS).
const vkLayouts = {
  'uz': [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ʻ'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', 'oʻ', 'gʻ'],
  ],
  'ru': [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['й', 'ц', 'у', 'к', 'е', 'н', 'г', 'ш', 'щ', 'з', 'х'],
    ['ф', 'ы', 'в', 'а', 'п', 'р', 'о', 'л', 'д', 'ж', 'э'],
    ['я', 'ч', 'с', 'м', 'и', 'т', 'ь', 'б', 'ю', 'ъ'],
  ],
  'en': [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ],
};

class VkState {
  final bool visible;
  final TextEditingController? target;
  final String lang;
  final bool shift;
  final VoidCallback? onEnter;
  const VkState({this.visible = false, this.target, this.lang = 'uz', this.shift = false, this.onEnter});

  VkState copyWith({bool? visible, TextEditingController? target, String? lang, bool? shift, VoidCallback? onEnter, bool clearTarget = false}) =>
      VkState(
        visible: visible ?? this.visible,
        target: clearTarget ? null : (target ?? this.target),
        lang: lang ?? this.lang,
        shift: shift ?? this.shift,
        onEnter: onEnter ?? this.onEnter,
      );
}

class VkController extends StateNotifier<VkState> {
  VkController() : super(const VkState());

  void show(TextEditingController c, {String lang = 'uz', VoidCallback? onEnter}) {
    state = VkState(visible: true, target: c, lang: lang, shift: false, onEnter: onEnter);
  }

  void hide() => state = state.copyWith(visible: false, clearTarget: true);

  void cycleLang() {
    const order = ['uz', 'ru', 'en'];
    state = state.copyWith(lang: order[(order.indexOf(state.lang) + 1) % 3], shift: false);
  }

  void toggleShift() => state = state.copyWith(shift: !state.shift);

  void key(String s) {
    final ch = (state.shift) ? s.toUpperCase() : s;
    _insert(ch);
  }

  void space() => _insert(' ');

  void enter() {
    final cb = state.onEnter;
    if (cb != null) {
      cb();
    } else {
      hide();
    }
  }

  void backspace() {
    final c = state.target;
    if (c == null) return;
    final text = c.text;
    final sel = c.selection;
    if (!sel.isValid) {
      if (text.isEmpty) return;
      c.value = TextEditingValue(text: text.substring(0, text.length - 1), selection: TextSelection.collapsed(offset: text.length - 1));
      return;
    }
    if (sel.start != sel.end) {
      final nt = text.replaceRange(sel.start, sel.end, '');
      c.value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: sel.start));
    } else if (sel.start > 0) {
      final nt = text.replaceRange(sel.start - 1, sel.start, '');
      c.value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: sel.start - 1));
    }
  }

  void _insert(String s) {
    final c = state.target;
    if (c == null) return;
    final text = c.text;
    final sel = c.selection;
    if (!sel.isValid) {
      c.value = TextEditingValue(text: text + s, selection: TextSelection.collapsed(offset: text.length + s.length));
      return;
    }
    final nt = text.replaceRange(sel.start, sel.end, s);
    c.value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: sel.start + s.length));
  }
}

final vkProvider = StateNotifierProvider<VkController, VkState>((_) => VkController());
