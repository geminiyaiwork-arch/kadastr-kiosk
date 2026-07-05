import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Joriy sahifадаги KField'lar TARTIBLI ro'yxati — telefon "Tab" (keyingi input)
/// va klaviatura AUTO-ochilishi/yopilishi (sahifада input bor/yo'qligiga qarab) uchun.
class VkFieldReg {
  final TextEditingController controller;
  final VoidCallback? onEnter;
  const VkFieldReg(this.controller, this.onEnter);
}

class VkFields extends StateNotifier<List<VkFieldReg>> {
  VkFields() : super(const []);

  void register(VkFieldReg r) {
    if (state.any((e) => e.controller == r.controller)) return;
    state = [...state, r];
  }

  void unregister(TextEditingController c) {
    if (!state.any((e) => e.controller == c)) return;
    state = state.where((e) => e.controller != c).toList();
  }
}

final vkFieldsProvider = StateNotifierProvider<VkFields, List<VkFieldReg>>((_) => VkFields());
