import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: T.navy,
    primary: T.blue,
    secondary: T.green,
    surface: Colors.white,
    onSurface: T.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: T.bg,
    fontFamily: 'Inter',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
