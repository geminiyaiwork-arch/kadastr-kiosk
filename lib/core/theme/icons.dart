import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Stroke SVG icons ported 1:1 from app.js ICONS + index.html nav icons.
/// The raw strings are stroke-only (no fill) — matching the web .ic svg CSS.
const Map<String, String> _svg = {
  // service icons (48x48)
  'property': '<svg viewBox="0 0 48 48"><path d="M7 22 24 8l17 14"/><path d="M11 19v18h12"/><circle cx="32" cy="32" r="7"/><path d="M37 37l6 6"/></svg>',
  'xatlov': '<svg viewBox="0 0 48 48"><rect x="10" y="8" width="28" height="34" rx="3"/><path d="M18 8V5h12v3"/><path d="M17 20h14M17 27h14"/><path d="M17 34h7"/><path d="M30 33l3 3 5-6"/></svg>',
  'document': '<svg viewBox="0 0 48 48"><path d="M12 6h17l8 8v22a3 3 0 0 1-3 3H12a3 3 0 0 1-3-3V9a3 3 0 0 1 3-3z"/><path d="M29 6v9h9"/><circle cx="22" cy="26" r="5.5"/><path d="M26 30l6 6"/></svg>',
  'appeal': '<svg viewBox="0 0 48 48"><rect x="6" y="10" width="36" height="26" rx="4"/><path d="M6 14l18 13 18-13"/><path d="M16 40h16"/></svg>',
  'reception': '<svg viewBox="0 0 48 48"><circle cx="19" cy="16" r="7"/><path d="M6 40c1.5-8 6.5-12 13-12s11.5 4 13 12"/><circle cx="35" cy="29" r="8"/><path d="M35 25v4l3 2"/></svg>',
  'illegal': '<svg viewBox="0 0 48 48"><path d="M8 38 16 12l10 18 6-10 8 18z"/><circle cx="33" cy="13" r="6"/><path d="M33 10v4M33 16.5v.5"/></svg>',
  'districts': '<svg viewBox="0 0 48 48"><path d="M8 12l10-4 12 4 10-4v28l-10 4-12-4-10 4z"/><path d="M18 8v28M30 12v28"/></svg>',
  'ai': '<svg viewBox="0 0 48 48"><rect x="9" y="14" width="30" height="22" rx="6"/><circle cx="18" cy="25" r="2.6"/><circle cx="30" cy="25" r="2.6"/><path d="M24 14V7M20 7h8"/><path d="M9 22H5v8h4M39 22h4v8h-4"/><path d="M18 31.5c2 1.6 10 1.6 12 0"/></svg>',
  'phones': '<svg viewBox="0 0 48 48"><path d="M14 6h10l3 9-5 4a22 22 0 0 0 8 8l4-5 9 3v10c0 2-2 4-4 4C22 39 9 26 9 9c0-2 2-3 5-3z" transform="translate(2,1) scale(.92)"/><path d="M32 8c4 1 7 4 8 8M32 2c7 1 12 6 13 13"/></svg>',
  'pin': '<svg viewBox="0 0 24 24"><path d="M12 21s-7-6-7-11a7 7 0 0 1 14 0c0 5-7 11-7 11z"/><circle cx="12" cy="10" r="2.6"/></svg>',
  'phone': '<svg viewBox="0 0 24 24"><path d="M7 3h5l1.5 4.5L11 9.6a11 11 0 0 0 4 4l2.1-2.5L21.5 13v5c0 1-1 2-2 2C11 19.4 4.6 13 4.5 5c0-1 1-2 2.5-2z"/></svg>',
  'mic': '<svg viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
  'send': '<svg viewBox="0 0 24 24"><path d="M3 12 21 4l-4 16-5.5-5.5L3 12z"/><path d="M11.5 14.5 21 4"/></svg>',
  // bottom-nav icons (24x24)
  'navHome': '<svg viewBox="0 0 24 24"><path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10.5V20h13v-9.5"/></svg>',
  'navServices': '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/></svg>',
  'navNews': '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9h8M8 13h8M8 17h5"/></svg>',
  'navSocial': '<svg viewBox="0 0 24 24"><circle cx="6" cy="12" r="2.6"/><circle cx="17" cy="6" r="2.6"/><circle cx="17" cy="18" r="2.6"/><path d="M8.3 10.8 14.7 7.2M8.3 13.2l6.4 3.6"/></svg>',
  'globe': '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.8 2.6 4 5.6 4 9s-1.2 6.4-4 9c-2.8-2.6-4-5.6-4-9s1.2-6.4 4-9z"/></svg>',
};

/// Build a stroked icon widget. Injects fill=none + stroke=color into the <svg> root.
Widget kIcon(String name, {required double size, required Color color, double stroke = 1.7}) {
  final raw = _svg[name];
  if (raw == null) return SizedBox(width: size, height: size);
  final full = raw.replaceFirst(
    '<svg ',
    '<svg fill="none" stroke="currentColor" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round" ',
  );
  return SvgPicture.string(
    full,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}
