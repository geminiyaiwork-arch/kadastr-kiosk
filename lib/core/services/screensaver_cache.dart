import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../env.dart';
import '../network/api_client.dart';

/// Zastavka videolarini KOMPYUTERGA (lokal) keshlaydi:
///  - serverdagi ro'yxatni oladi ([{id, url}]),
///  - YANGI videoni bir marta yuklab qo'yadi (keyin internetsiz o'ynaydi),
///  - serverdan O'CHIRILGAN videoni lokaldan ham o'chiradi,
///  - internet bo'lmasa — mavjud keshlangan fayllar bilan ishlaydi.
/// Zastavka har safar internetdan emas, shu LOKAL fayllardan o'ynaydi (tez + barqaror).
/// Har chaqirilганда qayta sinxronlanadi → server yangi qo'shsa/o'chirsa darhol aks etadi.
final screensaverCacheProvider = FutureProvider<List<String>>((ref) async {
  final dio = ref.read(dioProvider);

  Directory dir;
  try {
    final base = await getApplicationSupportDirectory();
    dir = Directory('${base.path}/screensaver');
    if (!await dir.exists()) await dir.create(recursive: true);
  } catch (_) {
    return const <String>[];
  }

  // Serverdagi ro'yxat. Xato (oflayn) bo'lsa — mavjud keshlangan fayllarni qaytaramiz.
  List<Map> items;
  try {
    final r = await dio.get('/screensaver').timeout(const Duration(seconds: 8));
    items = ((r.data as List?) ?? const []).whereType<Map>().toList();
  } catch (_) {
    return _localVideos(dir);
  }

  final wantIds = <String>{};
  final localPaths = <String>[];
  for (final e in items) {
    final id = '${e['id'] ?? ''}';
    final url = '${e['url'] ?? ''}';
    if (id.isEmpty || url.isEmpty) continue;
    wantIds.add(id);
    final ext = url.contains('.') ? url.substring(url.lastIndexOf('.')) : '.mp4';
    final f = File('${dir.path}/$id$ext');
    // Fayl yo'q yoki buzuq (juda kichik) bo'lsa — yuklab olamiz
    if (!await f.exists() || (await f.length()) < 1024) {
      final full = url.startsWith('http') ? url : '${Env.portalOrigin}$url';
      try {
        await dio.download(full, f.path,
            options: Options(receiveTimeout: const Duration(minutes: 5)));
      } catch (_) {
        // yuklab bo'lmadi — o'tkazamiz (boshqa keshlanganlari o'ynaydi)
        continue;
      }
    }
    if (await f.exists()) localPaths.add(f.path);
  }

  // Serverda YO'Q (o'chirilgan) videolarni lokaldan ham o'chiramiz
  try {
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final idOnly = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      if (!wantIds.contains(idOnly)) {
        try { f.deleteSync(); } catch (_) {}
      }
    }
  } catch (_) {}

  return localPaths;
});

List<String> _localVideos(Directory dir) {
  try {
    return dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final p = f.path.toLowerCase();
          return p.endsWith('.mp4') || p.endsWith('.webm') || p.endsWith('.mov');
        })
        .map((f) => f.path)
        .toList();
  } catch (_) {
    return const <String>[];
  }
}
