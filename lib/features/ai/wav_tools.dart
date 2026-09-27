import 'dart:math';
import 'dart:typed_data';

/// PCM WAV ma'lumotlari (faqat 16-bit PCM qo'llanadi).
class WavInfo {
  const WavInfo({
    required this.dataOffset,
    required this.dataLength,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });
  final int dataOffset;
  final int dataLength;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  int get bytesPerMs => sampleRate * channels * (bitsPerSample ~/ 8) ~/ 1000;
  int get blockAlign => channels * (bitsPerSample ~/ 8);
}

String _ascii(Uint8List b, int off) =>
    String.fromCharCodes([b[off], b[off + 1], b[off + 2], b[off + 3]]);
int _u32(Uint8List b, int off) => b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);
int _u16(Uint8List b, int off) => b[off] | (b[off + 1] << 8);

/// RIFF/WAVE sarlavhasini YUMSHOQ o'qiydi. `record_windows` sarlavhasi 46 bayt
/// (WAVEFORMATEX 18), Android 44 — ikkalasi ham; `data` hajmi 0/noto'g'ri bo'lsa
/// fayl oxirigacha olinadi. PCM16 bo'lmasa null.
WavInfo? parseWav(Uint8List b) {
  if (b.length < 44) return null;
  if (_ascii(b, 0) != 'RIFF' || _ascii(b, 8) != 'WAVE') return null;
  int? fmt;
  int? data;
  var dataLen = 0;
  var off = 12;
  while (off + 8 <= b.length) {
    final id = _ascii(b, off);
    final sz = _u32(b, off + 4);
    if (id == 'fmt ') fmt = off + 8;
    if (id == 'data') {
      data = off + 8;
      final rest = b.length - data;
      dataLen = (sz <= 0 || sz > rest) ? rest : sz;
      break;
    }
    if (sz > b.length) break;
    off += 8 + sz + (sz & 1);
  }
  if (data == null) {
    // Nostandart tekislash (padding) — birinchi 256 baytda 'data' ni qidiramiz.
    for (var i = 12; i + 8 <= min(b.length, 256); i++) {
      if (b[i] == 0x64 && b[i + 1] == 0x61 && b[i + 2] == 0x74 && b[i + 3] == 0x61) {
        data = i + 8;
        final sz = _u32(b, i + 4);
        final rest = b.length - data;
        dataLen = (sz <= 0 || sz > rest) ? rest : sz;
        break;
      }
    }
  }
  if (fmt == null || data == null || fmt + 16 > b.length) return null;
  final format = _u16(b, fmt);
  final channels = _u16(b, fmt + 2);
  final rate = _u32(b, fmt + 4);
  final bits = _u16(b, fmt + 14);
  if ((format != 1 && format != 0xFFFE) || bits != 16 || channels < 1 || rate < 4000) return null;
  return WavInfo(
      dataOffset: data,
      dataLength: dataLen - (dataLen % (2 * channels)),
      sampleRate: rate,
      channels: channels,
      bitsPerSample: bits);
}

/// 44-baytli kanonik PCM16 WAV yasaydi.
Uint8List buildWav(Uint8List pcm, {required int sampleRate, int channels = 1}) {
  final out = Uint8List(44 + pcm.length);
  final bd = ByteData.sublistView(out);
  void tag(int off, String s) {
    for (var i = 0; i < 4; i++) {
      out[off + i] = s.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  bd.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * 2, Endian.little);
  bd.setUint16(32, channels * 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bd.setUint32(40, pcm.length, Endian.little);
  out.setRange(44, out.length, pcm);
  return out;
}

/// Boshidagi [startMs] ms ni kesib tashlaydi (nutqdan oldingi sukut). Kesish natijasi
/// [minKeepMs] dan qisqa bo'lsa yoki WAV o'qilmasa — asl baytlar qaytadi.
Uint8List trimWavStart(Uint8List wav, int startMs, {int minKeepMs = 300}) {
  if (startMs <= 0) return wav;
  final info = parseWav(wav);
  if (info == null) return wav;
  var cut = startMs * info.bytesPerMs;
  cut -= cut % info.blockAlign;
  if (cut <= 0 || info.dataLength - cut < minKeepMs * info.bytesPerMs) return wav;
  final pcm = Uint8List.sublistView(wav, info.dataOffset + cut, info.dataOffset + info.dataLength);
  return buildWav(pcm, sampleRate: info.sampleRate, channels: info.channels);
}

/// Faqat birinchi [maxMs] ms ni qoldiradi (zastavkada chaqiruv so'zini tekshirish uchun
/// qisqa bo'lak). Qisqaroq bo'lsa yoki WAV o'qilmasa — asl baytlar.
Uint8List truncateWav(Uint8List wav, int maxMs) {
  final info = parseWav(wav);
  if (info == null || maxMs <= 0) return wav;
  var keep = maxMs * info.bytesPerMs;
  keep -= keep % info.blockAlign;
  if (keep >= info.dataLength) return wav;
  final pcm = Uint8List.sublistView(wav, info.dataOffset, info.dataOffset + keep);
  return buildWav(pcm, sampleRate: info.sampleRate, channels: info.channels);
}

/// (RMS dBFS, peak dBFS) — to'g'ri `data` ofsetidan (avval 44 deb taxmin qilinardi).
(double, double) wavLevels(Uint8List wav) {
  final info = parseWav(wav);
  final start = info?.dataOffset ?? 44;
  final end = info == null ? wav.length : info.dataOffset + info.dataLength;
  if (end - start < 2) return (-160, -160);
  var sum = 0.0;
  var cnt = 0;
  var peak = 0;
  for (var i = start; i + 1 < end; i += 2) {
    var s = wav[i] | (wav[i + 1] << 8);
    if (s >= 32768) s -= 65536;
    final a = s.abs();
    if (a > peak) peak = a;
    sum += s.toDouble() * s.toDouble();
    cnt++;
  }
  if (cnt == 0) return (-160, -160);
  final rms = sqrt(sum / cnt);
  double db(double v) => 20 * (log(v / 32768.0 + 1e-9) / ln10);
  return (db(rms), db(peak.toDouble()));
}
