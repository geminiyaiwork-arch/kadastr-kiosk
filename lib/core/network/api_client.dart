import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';

/// Shared Dio client for the kiosk REST API (all endpoints public).
///
/// KEEP-ALIVE (1.9.48): dio'ning standart HttpClient'i bo'sh ulanishni 3 soniyada
/// yopadi (`idleTimeout = 3s`) → foydalanuvchi gapirib bo'lguncha (>3s) ulanish yopilib,
/// HAR /stt so'rovi yangi TCP+TLS qo'l siqishini kutardi (~2-3 RTT). Endi 50s ochiq
/// turadi (nginx keepalive_timeout 65s dan kichik) + ovoz boshida /health bilan isitiladi.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBase,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.json,
  ));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..idleTimeout = const Duration(seconds: 50),
  );
  return dio;
});

/// Resolve a JSON-returned relative media path against the API ORIGIN
/// (not /api/v1) — screensaver, news media, etc.
String resolveMedia(String path) {
  if (path.startsWith('http')) return path;
  return '${Env.apiOrigin}${path.startsWith('/') ? '' : '/'}$path';
}
