import 'package:flutter/material.dart';

/// Design tokens — 1:1 with the web kiosk styles.css :root variables.
class T {
  // Brand
  static const navy = Color(0xFF10266B);
  static const navy2 = Color(0xFF1B3A8C);
  static const navy3 = Color(0xFF23479F);
  static const blue = Color(0xFF2F6FE3);
  static const blueD = Color(0xFF1E55C0);
  static const sky = Color(0xFFE8F0FC);
  static const green = Color(0xFF1FA463);

  // Surfaces
  static const bg = Color(0xFFF2F5FA);
  static const card = Colors.white;
  static const line = Color(0xFFE3E9F2);
  static const ink = Color(0xFF1E2A3B);
  static const muted = Color(0xFF6B7A90);

  // Letterbox / dark surfaces
  static const letterbox = Color(0xFF0C1430);
  static const camDark = Color(0xFF0C1426);
  static const aiDark = Color(0xFF141414);

  // Virtual keyboard
  static const vkPanel = Color(0xFF1B2A4A);
  static const vkKey = Color(0xFF33446B);
  static const vkWide = Color(0xFF3D5180);
  static const vkKeyShadow = Color(0xFF22304D);

  // Status / accents
  static const recRed = Color(0xFFE23B3B);
  static const errText = Color(0xFFC0392B);
  static const errBg = Color(0xFFFDE8E8);
  static const greenTint = Color(0xFFE7F6EE);
  static const enterShadow = Color(0xFF167A4A);

  // Radii
  static const rCard = 16.0;
  static const rLg = 22.0;
  static const rModal = 24.0;
  static const rSvc = 26.0;
  static const rInput = 14.0;
  static const rBtn = 16.0;
  static const rChip = 22.0;

  // Shadow
  static const shadow = <BoxShadow>[
    BoxShadow(color: Color(0x1410266B), offset: Offset(0, 6), blurRadius: 22),
  ];

  // Gradients
  static const gNavy = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy2, navy],
  );
  static const gNavyH = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [navy2, navy],
  );
}
