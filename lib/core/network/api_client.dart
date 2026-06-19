import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';

/// Shared Dio client for the kiosk REST API (all endpoints public).
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBase,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.json,
  ));
  return dio;
});

/// Resolve a JSON-returned relative media path against the API ORIGIN
/// (not /api/v1) — screensaver, news media, etc.
String resolveMedia(String path) {
  if (path.startsWith('http')) return path;
  return '${Env.apiOrigin}${path.startsWith('/') ? '' : '/'}$path';
}
