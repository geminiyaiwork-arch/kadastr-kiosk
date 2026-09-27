import 'dart:async';
import 'dart:convert';

/// NDJSON (bir qatorda bitta JSON obyekt) oqimini BO'LAKMA-BO'LAK dekodlaydi.
///
/// - UTF-8 ko'p-baytli belgi ikki TCP bo'lagi orasida bo'linib kelsa ham to'g'ri
///   yig'iladi (`utf8.decoder` chunked konversiya).
/// - Qator bir necha bo'lakka bo'linib kelsa `LineSplitter` birlashtiradi
///   (`\n`, `\r\n` qo'llanadi); oxirgi `\n`siz qator ham oqim yopilganda chiqadi.
/// - Bo'sh qatorlar tashlanadi; buzuq JSON qator [onMalformed] ga beriladi va
///   o'tkazib yuboriladi (butun javob to'xtamaydi).
///
/// DIQQAT: `stream.transform(utf8.decoder)` dio'ning `Stream<Uint8List>`ida runtime
/// tip-xatosi beradi — shuning uchun `bind` ishlatiladi.
Stream<Map<String, dynamic>> decodeNdjson(
  Stream<List<int>> bytes, {
  void Function(String line, Object error)? onMalformed,
}) async* {
  final lines = const LineSplitter().bind(utf8.decoder.bind(bytes));
  await for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    Object? v;
    try {
      v = jsonDecode(line);
    } catch (e) {
      onMalformed?.call(line, e);
      continue;
    }
    if (v is Map<String, dynamic>) {
      yield v;
    } else if (v is Map) {
      yield Map<String, dynamic>.from(v);
    } else {
      onMalformed?.call(line, const FormatException('not a JSON object'));
    }
  }
}
