import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';
import 'api_client.dart';
import 'models.dart';

/// Real estate / land statistics — live /stats, offline fallback to bundled data.json.
/// 24/7 kioskda RAQAMLAR ESKIRMASIN: 30 daqiqada bir o'zini yangilaydi (admin qiymatni
/// o'zgartirsa yoki manba yangilansa — kiosk qayta yuklamasdan yangilanadi).
final statsProvider = FutureProvider<Stats>((ref) async {
  final t = Timer(const Duration(minutes: 30), ref.invalidateSelf);
  ref.onDispose(t.cancel);
  final dio = ref.read(dioProvider);
  try {
    final r = await dio.get('/stats');
    return Stats.fromJson(Map<String, dynamic>.from(r.data as Map));
  } catch (_) {
    try {
      final raw = await rootBundle.loadString('assets/content/data.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['stats'] is Map) {
        return Stats.fromJson(Map<String, dynamic>.from(m['stats'] as Map));
      }
    } catch (_) {}
    return Stats.empty;
  }
});

/// Districts + city offices.
final districtsProvider = FutureProvider<List<District>>((ref) async {
  final dio = ref.read(dioProvider);
  final r = await dio.get('/districts');
  final list = (r.data as List)
      .map((e) => District.fromJson(Map<String, dynamic>.from(e as Map)))
      .where((d) => d.active)
      .toList();
  return list;
});

/// Kiosk news feed.
final newsProvider = FutureProvider<List<NewsItem>>((ref) async {
  final dio = ref.read(dioProvider);
  final r = await dio.get('/news', queryParameters: {'target': 'kiosk'});
  final data = r.data;
  if (data is! List) return const [];
  return data
      .map((e) => NewsItem.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});

List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) f) =>
    data is List ? data.map((e) => f(Map<String, dynamic>.from(e as Map))).toList() : <T>[];

/// 937-xatlov — Andijon (viloyat jami + tumanlar + barcha ustunlar). Excel'дагидек.
final xatlov937Provider = FutureProvider<Map<String, dynamic>>((ref) async {
  final r = await ref.read(dioProvider).get('/xatlov937');
  return Map<String, dynamic>.from(r.data as Map);
});

final avatarProvider = FutureProvider<AvatarConfig>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/avatar');
    return AvatarConfig.fromJson(Map<String, dynamic>.from(r.data as Map));
  } catch (_) {
    return const AvatarConfig();
  }
});

/// Admin yuklagan ZASTAVKA videolari (kutish ekranida to'liq ekran o'ynaydi).
/// URL nisbiy keladi ("/screensaver/x.mp4") — portal domeniga to'ldiriladi.
final screensaverProvider = FutureProvider<List<String>>((ref) async {
  try {
    final r = await ref.read(dioProvider).get('/screensaver');
    return (r.data as List? ?? [])
        .map((e) => '${(e as Map)['url'] ?? ''}')
        .where((u) => u.isNotEmpty)
        .map((u) => u.startsWith('http') ? u : '${Env.portalOrigin}$u')
        .toList();
  } catch (_) {
    return const <String>[];
  }
});

final socialProvider = FutureProvider<List<SocialLink>>((ref) async =>
    _list((await ref.read(dioProvider).get('/social')).data, SocialLink.fromJson));

final phonesProvider = FutureProvider<List<PhoneEntry>>((ref) async =>
    _list((await ref.read(dioProvider).get('/phones')).data, PhoneEntry.fromJson));

/// Xodimlar (telefon-direktoriya) — kiosk Telefonlar bo'limi. autoDispose: davomat/online yangilanadi.
final employeesProvider = FutureProvider.autoDispose<List<Employee>>((ref) async =>
    _list((await ref.read(dioProvider).get('/employees')).data, Employee.fromJson));

/// Bo'limlar — murojaat bo'lim tanlash.
final departmentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final r = await ref.read(dioProvider).get('/departments');
  return ((r.data as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
});

/// AI "yuklanmoqda" holati (7 soatlik foizli progress). {loading, progress, remaining, hours}.
final aiWarmupProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final r = await ref.read(dioProvider).get('/ai/warmup');
  return Map<String, dynamic>.from(r.data as Map);
});

/// AI yuklanmoqda-payti mikrofon TINGLAMAydi (canListen shundan foydalanadi).
final aiWarmupLoadingProvider = StateProvider<bool>((_) => false);

final receptionProvider = FutureProvider<List<ReceptionManager>>((ref) async =>
    _list((await ref.read(dioProvider).get('/reception')).data, ReceptionManager.fromJson));

/// Rahbar qabuli statistikasi (keldi / hal bo'ldi / hal bo'lmadi) — kiosk pastida.
final receptionStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final r = await ref.read(dioProvider).get('/reception/stats');
  return Map<String, dynamic>.from(r.data as Map);
});

final documentsProvider = FutureProvider<List<DocItem>>((ref) async =>
    _list((await ref.read(dioProvider).get('/documents')).data, DocItem.fromJson));

/// Illegal-lands district counts (public, aggregate only).
final illegalSummaryProvider = FutureProvider<IllegalSummary>((ref) async {
  final r = await ref.read(dioProvider).get('/illegal-lands/summary');
  return IllegalSummary.fromJson(Map<String, dynamic>.from(r.data as Map));
});

/// MyID OAuth (QR) — start a session and poll the verified personal record.
final myidRepoProvider = Provider((ref) => MyIdRepo(ref));

class MyIdRepo {
  MyIdRepo(this.ref);
  final Ref ref;

  /// {state, auth_url} or {error}
  Future<Map<String, dynamic>> startSession() async {
    final r = await ref.read(dioProvider).post('/myid/session');
    return Map<String, dynamic>.from(r.data as Map);
  }

  /// Web SDK kamera-yuz: MyID web sessiyasini ochadi. {session_id, state, web_url} yoki {error}.
  /// JSHSHIR yoki pasport+tug'ilgan kun bilan; web_url WebView2'да ochiladi (kamera).
  Future<Map<String, dynamic>> webSession({
    required String mode, // jshshir | passport
    String? jshshir,
    String? passport,
    String? birth,
    String lang = 'uz',
  }) async {
    final r = await ref.read(dioProvider).post('/myid/web-session', data: {
      'mode': mode,
      if (jshshir != null) 'jshshir': jshshir,
      if (passport != null) 'passport': passport,
      if (birth != null) 'birth': birth,
      'lang': lang,
    });
    return Map<String, dynamic>.from(r.data as Map);
  }

  /// Poll the MyID-verified illegal-lands record. {ready, error?, found, name, pinfl, records}
  Future<Map<String, dynamic>> myRecord(String state) async {
    final r = await ref.read(dioProvider).get('/illegal-lands/my-record', queryParameters: {'state': state});
    return Map<String, dynamic>.from(r.data as Map);
  }
}

/// Personal lookup by JSHSHIR or birth+passport (returns the person's records).
final illegalRepoProvider = Provider((ref) => IllegalRepo(ref));

class IllegalRepo {
  IllegalRepo(this.ref);
  final Ref ref;

  Future<List<IllegalRecord>> byJshshir(String jshshir) =>
      _lookup({'jshshir': jshshir.replaceAll(RegExp(r'\D'), '')});

  Future<List<IllegalRecord>> byPassport(String passport, String birth) =>
      _lookup({'passport': passport.trim(), 'birth': birth.trim()});

  Future<List<IllegalRecord>> _lookup(Map<String, dynamic> q) async {
    final r = await ref.read(dioProvider).get('/illegal-lands/lookup', queryParameters: q);
    final m = Map<String, dynamic>.from(r.data as Map);
    return _list(m['records'], IllegalRecord.fromJson);
  }

  /// Kamera Face-ID: yuz fotosi + JSHSHIR/pasport → MyID embedded → {verified, profile, records} yoki {error}.
  Future<Map<String, dynamic>> verifyFace({
    required String mode, // jshshir | passport
    String? jshshir,
    String? passport,
    String? birth,
    required String photo, // data URI base64
  }) async {
    final r = await ref.read(dioProvider).post('/illegal-lands/verify-face', data: {
      'mode': mode,
      if (jshshir != null) 'jshshir': jshshir,
      if (passport != null) 'passport': passport,
      if (birth != null) 'birth': birth,
      'photo': photo,
    });
    return Map<String, dynamic>.from(r.data as Map);
  }
}
