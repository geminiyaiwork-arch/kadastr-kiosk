import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/tokens.dart';

/// Virtual klaviatura sozlamalari — ranglar, o'lcham, bosish-effekti, joyi.
/// shared_preferences'da saqlanadi → ilova qayta ochilganda tiklanadi.
class VkSettings {
  final Color panel; // panel foni
  final Color key; // tugma foni
  final Color text; // matn rangi
  final double scale; // 0.8 – 1.35 (tugma o'lchami)
  final bool glow; // bosganda yonish effekti
  final Offset? pos; // klaviatura joyi (null = pastda, markazda)
  const VkSettings({
    this.panel = T.vkPanel,
    this.key = T.vkKey,
    this.text = Colors.white,
    this.scale = 1.0,
    this.glow = true,
    this.pos,
  });

  VkSettings copyWith(
          {Color? panel, Color? key, Color? text, double? scale, bool? glow, Offset? pos, bool clearPos = false}) =>
      VkSettings(
        panel: panel ?? this.panel,
        key: key ?? this.key,
        text: text ?? this.text,
        scale: scale ?? this.scale,
        glow: glow ?? this.glow,
        pos: clearPos ? null : (pos ?? this.pos),
      );

  Map<String, dynamic> toJson() => {
        'panel': panel.value,
        'key': key.value,
        'text': text.value,
        'scale': scale,
        'glow': glow,
        'px': pos?.dx,
        'py': pos?.dy,
      };

  factory VkSettings.fromJson(Map<String, dynamic> j) => VkSettings(
        panel: j['panel'] != null ? Color(j['panel'] as int) : T.vkPanel,
        key: j['key'] != null ? Color(j['key'] as int) : T.vkKey,
        text: j['text'] != null ? Color(j['text'] as int) : Colors.white,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
        glow: j['glow'] as bool? ?? true,
        pos: (j['px'] != null && j['py'] != null)
            ? Offset((j['px'] as num).toDouble(), (j['py'] as num).toDouble())
            : null,
      );
}

class VkSettingsController extends StateNotifier<VkSettings> {
  VkSettingsController() : super(const VkSettings()) {
    _load();
  }
  static const _k = 'vk_settings_v1';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_k);
      if (s != null) state = VkSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  void _update(VkSettings s) {
    state = s;
    _save();
  }

  void setPanel(Color c) => _update(state.copyWith(panel: c));
  void setKey(Color c) => _update(state.copyWith(key: c));
  void setText(Color c) => _update(state.copyWith(text: c));
  void setScale(double s) => _update(state.copyWith(scale: s.clamp(0.75, 1.35)));
  void toggleGlow() => _update(state.copyWith(glow: !state.glow));
  void setPos(Offset o) => _update(state.copyWith(pos: o));
  void resetPos() => _update(state.copyWith(clearPos: true));
  void reset() => _update(const VkSettings());
}

final vkSettingsProvider =
    StateNotifierProvider<VkSettingsController, VkSettings>((_) => VkSettingsController());
