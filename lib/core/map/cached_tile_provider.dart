import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// OSM tile'larni DISKGA keshlovchi provider — bir marta ko'rilган tile keyin
/// internetsiz (tez) yuklanadi. Kiosk uchun: xarita bir marta ochilса, o'sha hudud oflayn.
class CachedTileProvider extends TileProvider {
  CachedTileProvider(this._dir);
  final Directory _dir;

  static Future<CachedTileProvider> create() async {
    Directory dir;
    try {
      final base = await getApplicationSupportDirectory();
      dir = Directory('${base.path}/maptiles');
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (_) {
      dir = Directory.systemTemp;
    }
    return CachedTileProvider(dir);
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    final f = File('${_dir.path}/${coordinates.z}_${coordinates.x}_${coordinates.y}.png');
    return _DiskTileImage(url, f, headers);
  }
}

class _DiskTileImage extends ImageProvider<_DiskTileImage> {
  _DiskTileImage(this.url, this.file, this.headers);
  final String url;
  final File file;
  final Map<String, String> headers;

  @override
  Future<_DiskTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_DiskTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    Uint8List bytes;
    // 1) Diskда bormi?
    try {
      if (await file.exists() && (await file.length()) > 0) {
        bytes = await file.readAsBytes();
        final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
        return decode(buf);
      }
    } catch (_) {}
    // 2) Yuklab olib keshlaymiz
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('User-Agent', headers['User-Agent'] ?? 'uz.andkadastrai.kiosk');
      final resp = await req.close();
      if (resp.statusCode != 200) throw Exception('tile ${resp.statusCode}');
      bytes = await consolidateHttpClientResponseBytes(resp);
      try {
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: false);
      } catch (_) {}
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buf);
    } finally {
      client.close();
    }
  }

  @override
  bool operator ==(Object other) => other is _DiskTileImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

/// Keshlangan tile-provider'ни bir marta yaratib qayta ishlatish (FutureProvider).
CachedTileProvider? _cached;
Future<CachedTileProvider> obtainCachedTileProvider() async =>
    _cached ??= await CachedTileProvider.create();
