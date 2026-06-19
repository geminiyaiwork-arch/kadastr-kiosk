I'll merge these 4 audits into one prioritized fix-list. Let me deduplicate overlapping findings (Inter font, secTitle uppercase, statsLabel opacity, gNavyH gradient, PageHead specs, logo cross-fade, AI avatar) across the audits.

# ZipGo/Kadastr Kiosk — Unified 1:1 Visual Fidelity Fix-List

## 1. CRITICAL (breaks the look)

- **`pubspec.yaml` + `lib/core/theme/app_theme.dart`** — Inter font not bundled; app renders in Segoe UI default. Add `assets/fonts/` with 6 weights (Regular/Medium/SemiBold/Bold/ExtraBold/Black = 400/500/600/700/800/900), declare each weight in `pubspec.yaml fonts:`, uncomment `fontFamily: 'Inter'` in app_theme — globally fixes every size/weight metric.
- **`lib/shell/kiosk_shell.dart:16-17`** — service variant colors swapped: `('xatlov','xatlov','blue')`→`'green'` and `('docs','document','green')`→`'blue'` (web: xatlov=green, document=blue).
- **`lib/features/ai/ai_screen.dart`** — non-data avatar is a 420px circle floating on dark bg; web is full-bleed `Positioned.fill` `Image cover` (radius 0, no border); SVG/icon fallback ~720px. Data state = 240px circle with `border: 6px solid #fff`.
- **`lib/features/ai/ai_screen.dart`** — status is bare white text; web is a navy-text white pill: `padding: 48/18`, `borderRadius: 44`, `bg Color(0xEBFFFFFF)`, `boxShadow Color(0x2410266B) offset(0,6) blur22`, `color: T.navy`, `Positioned(bottom:60)` centered.
- **`lib/features/info/info_screens.dart` (XatlovScreen)** — missing both `.tbl` data tables (status 6 rows + district TOP-10 10 rows from `arizalar.holat`/`arizalar.tuman`); currently only a static paragraph. Add real tables.
- **`lib/features/info/info_screens.dart` (DocsScreen)** — renders N stacked KV cards; web is ONE `.tbl` table (sky-header navy/800 th, fee/term right-aligned `.num`, border-bottom T.line, font 22) + `docNeed` info card + demo note.
- **`lib/features/news/news_screen.dart`** — news detail missing `.nd-body` paragraph entirely; add `Text(body, fontSize:28, height:1.6, color:T.ink)` (pre-line) between title and back button.
- **`lib/shell/lang_modal.dart:48-54`** — `.lang-opt` default is sky-filled with no border (inverts web); change default to `color: Colors.white, border: Border.all(color: T.line, width: 2), radius 16`, with pressed state → `bg T.sky + border T.blue`.

## 2. HIGH (clearly visible)

### Animations / feel (all missing)
- **`lib/shell/kiosk_shell.dart`** — fadeUp page transition missing; wrap scaffold body in `TweenAnimationBuilder` keyed by route: opacity 0→1, dy 16→0, 400ms, easeOut.
- **`lib/shell/kiosk_shell.dart:77`** — header logo static; add logo1↔logo2 `AnimatedSwitcher` (FadeTransition ~600ms) on randomized 8000–10000ms `Timer.periodic`. Verify `assets/images/logo2.png` bundled.
- **NEW `lib/features/attract/attract_screen.dart`** — attract/screensaver missing entirely; gradient 160° navy2→#0C1430, floating logo 280px (translateY 0↔-18, 3s ease-in-out), title 44/900 ls2, blinking subtitle 30px (.85↔.3, 1.8s), optional video carousel.
- **NEW `lib/core/idle/idle_controller.dart` + `lib/app.dart`** — idle reset missing; `Timer.periodic(1s)` + top-level `Listener(onPointerDown)`; 90s → `go('/')` + locale `uz`; 120s → push attract.
- **Press-scale missing** (extract shared `PressScale` widget): `lib/features/news/news_screen.dart:88` (.98), `lib/features/districts/districts_screen.dart:49` (.96), `lib/shell/kiosk_shell.dart:85` lang pill (.96), `lib/shell/kiosk_shell.dart:200` back-btn (.92).
- **`lib/shell/virtual_keyboard.dart`** — key press `:active` feedback missing; on tap-down set bg→`T.blue`, translateY 2px, shadow→`0 1px 0`.

### Layout / sizing
- **`lib/features/home/home_screen.dart:39`** — grid `childAspectRatio: 1` forces 321px-tall tiles; web is min-height 212 content-driven → set `childAspectRatio ≈ 1.5` (or content-height layout).
- **`lib/features/common/svc_tile.dart:35`** — add `constraints: BoxConstraints(minHeight: 212)` (web `.svc{min-height:212px}`).
- **`lib/features/districts/districts_screen.dart:26-35`** — `childAspectRatio: 2.5` makes ~198px tiles (web ~96px content); set ratio ≈ 5.1 or use `mainAxisExtent: 96`.
- **`lib/features/social/social_screen.dart:27`** — `childAspectRatio: 0.85` makes ~582px tiles (web ~320px); set ≈ 1.5 or `mainAxisExtent ≈ 320`.
- **`lib/features/social/social_screen.dart:43-56`** — remove inner `padding: EdgeInsets.all(10)`; put 2px `T.line` border + radius 14 directly on a 190×190 box clipping `QrImageView(size:190)`.
- **`lib/features/home/home_screen.dart:86`** — remove spurious third 27px `heroSub` line; hero renders only org (24/800) + title (44/900) per web.
- **`lib/features/common/kfield.dart:48`** — input padding `horizontal:18, vertical:16` → `horizontal:20, vertical:18`; remove/offset `isDense:true` so field ≈62px tall (web `.f-input{padding:18px 20px}`).
- **`lib/features/common/kfield.dart`** — multiline (`lines>1`) has no min-height; wrap in `ConstrainedBox(minHeight:150)` + `maxLines:null, minLines:lines` (web `.f-area{min-height:150px}`).
- **`lib/features/common/widgets.dart:99`** — KvRows value weight `w600` → `w700` (web `.res .v{font-weight:700}`).
- **`lib/features/common/widgets.dart:97-99`** — KvRows key hard-pinned `SizedBox(width:300)`; replace with intrinsic-width key + 16 gap + `Expanded` value (web `justify-content:space-between`).
- **`lib/features/property/property_screen.dart:107`** — missing per-mode `f-label` above input; pass `label: modes[_mode]`.
- **`lib/features/property/property_screen.dart` + `lib/core/i18n/strings.dart:46`** — `propPh` is single string; web has array of 3 per mode (`['Masalan: 03:09:01:01:01:1234','14 raqamli JSHSHIR','AA1234567']`); make `List<String>` and index by `_mode`.
- **`lib/features/property/property_screen.dart`** — missing centered demo line; append `Text(t['demo'], style:K.pgSub, textAlign:center)`.
- **`lib/features/property/property_screen.dart:100`** — seg2 inactive text color `T.ink` → `T.muted` (web inactive = muted).
- **`lib/features/phones/phones_screen.dart:52`** — phone tile padding `EdgeInsets.all(20)` → `symmetric(vertical:22, horizontal:26)`.
- **`lib/features/phones/phones_screen.dart`** — missing `pg-sub` demo footer; append centered `Text(t['demo'], style:K.pgSub)`.
- **`lib/features/news/news_screen.dart:106-109`** — flat `T.sky` thumbnail; web `thumbSVG` is a 2-color `LinearGradient` (TL→BR, default `['#7fae7f','#5d8f5d']`) + dark bottom band + 5 translucent rects.
- **`lib/features/news/news_screen.dart`** — video news missing play overlay; stack centered 54×54 circle `Color(0x9910266B)` + white ▶ over thumbnail when `mediaType=='video'`.
- **`lib/features/news/news_screen.dart:40`** — detail media height `520` → `620` (web max-height 620, cover, radius 18).
- **`lib/shell/lang_modal.dart:17`** — backdrop blur missing; add `BackdropFilter(blur 4)` layer + scrim `Color(0x990C1430)` (spec §8 requires blur).
- **`lib/core/i18n/strings.dart` `distKV`** — 6 labels vs web 7; restore `'Bo'lim'` (department-name) as first row (`vals[0]=name`), rename current first back to `'Rahbar'` → 7 rows.

### Section title / uppercase
- **`lib/features/home/home_screen.dart:33`** (+ other `secTitle` call sites) — `secTitle` not uppercased; render `(t['quick'] as String).toUpperCase()` (web `text-transform:uppercase`).

## 3. MEDIUM / POLISH

### Tokens / typography
- **`lib/core/theme/tokens.dart:59-63`** — `gNavyH` ≈141°; for CSS 120° use `begin: Alignment(-0.87,-0.5), end: Alignment(0.87,0.5)`.
- **`lib/core/theme/text_styles.dart`** — `statsLabel` `Colors.white70` (.70) → `Color(0xD9FFFFFF)` (.85).
- **`lib/core/theme/text_styles.dart`** — `statsValue` add `letterSpacing: 0.5` (web `.stats .v`).
- **`lib/core/theme/text_styles.dart`** — `heroTitle` add `letterSpacing: 0.5` (web `.hero h1`).
- **`lib/core/theme/text_styles.dart`** — `heroSub` color → `Colors.white.withOpacity(0.95)` (web `.hero p{opacity:.95}`).
- **`lib/features/home/home_screen.dart:117`** — stats divider `Colors.white24` (.235) → `Color(0x38FFFFFF)` (.22).
- **`lib/core/theme/text_styles.dart`** — centralize missing styles per spec §8.2 if currently inlined: `tableHead`(22/800), `tableCell`(22), `badge`(19/700), `seg`(21/700 muted), `ndTitle`(42/800), `ndBody`(28/1.6), `ndBack`(26/700), `phName/phDesc/phNum`, `socName(25/800)/socLink(20)`.

### PageHead (`lib/shell/kiosk_shell.dart`)
- Line 196: bottom margin `18` → `26`.
- Line 214: icon→title gap `18` → `20`.
- Line 211: back glyph `fontSize:40` → `34`.
- Lines 205-209: back-btn add `boxShadow: T.shadow`.
- Add `SizedBox(height:4)` between title and sub (web `pg-sub{margin-top:4px}`).

### Bottom nav (`lib/shell/kiosk_shell.dart:149`)
- Add `padding: EdgeInsets.symmetric(horizontal: 8)` (web `.kt-nav{padding:0 8px}`).

### Property seg2 (`lib/features/property/property_screen.dart`)
- Line 91: inter-button gap `10` → `12`.
- Line 92: padding `symmetric(vertical:16)` → `symmetric(vertical:16, horizontal:8)`.

### KField / cards / buttons
- **`lib/features/common/kfield.dart:34`** — label bottom margin `SizedBox(height:6)` → `8` (web `.f-label{margin:14px 0 8px}`).
- **`lib/features/common/widgets.dart:17`** — KCard margin `bottom:18` → `20`.
- **`lib/features/common/widgets.dart:64`** — KButton padding `symmetric(vertical:22, horizontal:30)` → `EdgeInsets.all(22)`.
- **`lib/features/common/widgets.dart`** — news-detail back via KButton; web `.nd-back` = weight 700, padding `18/40` (special-case from generic 800/22).

### Districts / phones / social inner gaps
- **`lib/features/districts/districts_screen.dart:74-75`** — add `SizedBox(height:3)` between name and count.
- **`lib/features/phones/phones_screen.dart:68`** — icon→text gap `16` → `20`.
- **`lib/features/phones/phones_screen.dart:73-74`** — add `SizedBox(height:3)` between name and dept.
- **`lib/features/social/social_screen.dart:57-60`** — add `SizedBox(height:16)` between name and link; link style `K.distCount`(19) → fontSize 20 muted.

### Virtual keyboard (`lib/shell/virtual_keyboard.dart`)
- Line 21-24: add panel `boxShadow: BoxShadow(Color(0x66000000), offset(0,-12), blur40)`.
- Line 25: padding `fromLTRB(16,12,16,20)` → `fromLTRB(16,14,16,18)`.
- Line 16-17: curve `Curves.easeOut` → `Cubic(0.2,0.8,0.2,1)`.
- Line 104: enter-key shadow → `T.enterShadow` (#167A4A) when `enter==true`.
- Line 92: widths — wide `150`→`140`, enter `150`→`160`, space `480`→`560`; regular keys flex-capped at maxWidth 96 (not fixed 92) to avoid 11-key `ru` row overflow.
- Line 42/99: row bottom margin `8`→`9`, key horizontal margin `4`→`4.5` (web `gap:9px`).
- Line 106: wide keys fontSize `32` → `30`.
- Lines 76-80: lang fn bg `#3D5180` → `Color(0x1FFFFFFF)`, weight `w700`→`w800`, vertical padding `10`→`12`, add `constraints: BoxConstraints(minWidth:78)`.
- Line 34: title color `Colors.white70` → `Color(0xFFCDD9EA)`.
- Line 51: wrap bottom row in `Padding(top: 4)`.
- **`lib/shell/kiosk_shell.dart`** — verify scroll body gets `padding-bottom: 720` when `vk.visible` (web `.vk-open .kt-body`); add if absent.

### Lang modal (`lib/shell/lang_modal.dart`)
- Line 37: h3 — stop reusing `K.cardH`(27/800); use `fontSize:32, w800, T.navy`, centered.
- Line 49: option padding `symmetric(vertical:20)` → `EdgeInsets.all(24)`.
- Line 40: option gaps `bottom:16` → 18px gaps; drop trailing margin on last option.
- Line 50: option alignment center → `centerLeft` (web left-default).

### AI screen polish (`lib/features/ai/ai_screen.dart`)
- Lines 62-68: exit-btn radius `20`→`24`, bg `Colors.white10`→`Color(0xEBFFFFFF)`, chevron `Colors.white`→`T.navy` w800, add `boxShadow Color(0x38000000) offset(0,6) blur20`.
- Lines 101-103: remove `AnimatedScale(speaking?1.04)` zoom on media avatar (web "JOYIDA TURADI"); apply static glow only.
- Lines 110-113: speaking accent green → blue `T.blue` (web glow `rgba(47,111,227,.45)`).
- Lines 132-136 (_DataCard): padding `28`→`34`, radius `20`→`24`, add `boxShadow Color(0x2410266B) offset(0,10) blur34`, maxWidth `900`→`1000`.
- Lines 140-141: data-txt fontSize `30`→`32`, add `height:1.45`, gap below `16`→`22`.
- Lines 144-154: table key `24`→`30`, value `26`→`30`, row padding `vertical:8` → `symmetric(vertical:16, horizontal:18)`, add per-row `Border(bottom: BorderSide(color:T.line))` except last.

### Icons / svc feel
- **`lib/core/theme/icons.dart` / `districts_screen.dart` / `phones_screen.dart`** — pass `stroke: 1.8` for `pin` (district) and phone icons (currently default 1.7; web uses 1.8).
- **`lib/features/common/svc_tile.dart:34`** — AnimatedScale duration `90`→`120ms` (web `.svc{transition:.12s}`).

### Misc polish
- **`lib/features/illegal/illegal_screen.dart`** — error text wrap in `ConstrainedBox(minHeight:24)` (web `min-height:24px`); `.ill-choose` bottom gap `12`→`4`.
- **`lib/features/news/news_screen.dart:118`** — only append `👁 views` when present; use real spacing widget (web 10px margin) not 3-space hack.
- **`lib/features/news/news_screen.dart:46`** — detail meta font `20`→`22`, color view count value with `T.blue`.
