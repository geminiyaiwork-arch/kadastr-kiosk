import 'package:flutter/material.dart';
import 'tokens.dart';

/// Typography — logical px inside the 1080×1920 canvas (from styles.css).
/// Inter is bundled in M5; until then the default family is used.
class K {
  static const clock = TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: T.navy, height: 1);
  static const date = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: T.muted);
  static const lang = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: T.navy);

  static const heroTitle = TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5,
      shadows: [Shadow(color: Color(0x59000000), offset: Offset(0, 3), blurRadius: 18)]);
  static const heroSub = TextStyle(fontSize: 27, fontWeight: FontWeight.w500, color: Color(0xF2FFFFFF), height: 1.4);
  static const heroOrg = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, height: 1.4,
      shadows: [Shadow(color: Color(0x80000000), offset: Offset(0, 2), blurRadius: 12)]);

  static const secTitle = TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: T.navy, letterSpacing: 2.5);
  static const svcLabel = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: T.ink, height: 1.3);

  static const statsTitle = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 3);
  static const statsValue = TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5);
  static const statsLabel = TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: Color(0xD9FFFFFF), height: 1.25);

  static const pgTitle = TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: T.navy);
  static const pgSub = TextStyle(fontSize: 23, color: T.muted);

  static const cardH = TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: T.navy);
  static const cardP = TextStyle(fontSize: 23, color: T.ink, height: 1.55);

  static const fLabel = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: T.navy);
  static const fInput = TextStyle(fontSize: 26, color: T.ink);
  static const btn = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white);

  static const distName = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: T.ink);
  static const distCount = TextStyle(fontSize: 19, color: T.muted);

  static const newsTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: T.ink, height: 1.35);
  static const newsDate = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: T.muted);

  static const navLabel = TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: Colors.white);
  static const aiStatus = TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: T.navy);
  static const langOpt = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: T.ink);
  static const kv = TextStyle(fontSize: 23, color: T.ink);
}
