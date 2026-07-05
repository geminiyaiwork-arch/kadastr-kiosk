import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';

/// "Kadastr pasportini shakllantirish" video roligini KOMPYUTERGA (lokal) keshlaydi:
///  - serverdan meta (o'lcham+versiya) oladi,
///  - lokal fayl o'lchami mos bo'lsa QAYTA yuklamaydi (tez + internetsiz ishlaydi),
///  - server yangi video qo'ysa (o'lcham o'zgarsa) — bir marta qayta yuklaydi,
///  - internet bo'lmasa mavjud keshlangan fayldan o'ynaydi (yo'q bo'lsa null → video ko'rsatilmaydi).
final docsVideoProvider = FutureProvider<String?>((ref) async {
  final dio = ref.read(dioProvider);

  Directory dir;
  try {
    final base = await getApplicationSupportDirectory();
    dir = Directory('${base.path}/docsvideo');
    if (!await dir.exists()) await dir.create(recursive: true);
  } catch (_) {
    return null;
  }
  final f = File('${dir.path}/kadastr-passport.mp4');

  int wantBytes = 0;
  try {
    final r = await dio.get('/docs/passport-video-meta').timeout(const Duration(seconds: 8));
    final m = (r.data as Map?) ?? const {};
    wantBytes = (m['bytes'] as num?)?.toInt() ?? 0;
  } catch (_) {
    // meta olinmadi (oflayn) — mavjud keshlangan fayl bo'lsa uni beramiz
    return (await f.exists() && (await f.length()) > 100000) ? f.path : null;
  }

  // Lokal fayl o'lchami serverникига mos bo'lsa — qayta yuklamaymiz
  if (await f.exists() && wantBytes > 0 && (await f.length()) == wantBytes) return f.path;

  try {
    final tmp = File('${f.path}.tmp');
    await dio.download('/docs/passport-video', tmp.path,
        options: Options(receiveTimeout: const Duration(minutes: 5)));
    if (await tmp.exists() && (await tmp.length()) > 100000) {
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    } else {
      try { await tmp.delete(); } catch (_) {}
    }
  } catch (_) {
    // yuklab bo'lmadi — eski kesh bo'lsa beramiz
  }
  return (await f.exists() && (await f.length()) > 100000) ? f.path : null;
});
