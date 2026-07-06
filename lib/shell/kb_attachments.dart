import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Telefon-klaviatura (QR) orqali kelgan HUJJAT (fayl / A4-rasm).
class KbFile {
  final String url, name, kind; // kind: 'file' | 'a4'
  const KbFile(this.url, this.name, this.kind);
  bool get isImage => kind == 'a4' || RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(url);
}

/// Telefondan yuklangan hujjatlar ro'yxati — murojaat ekrani o'qiydi, klaviatura to'ldiradi.
class KbAttachments extends StateNotifier<List<KbFile>> {
  KbAttachments() : super(const []);
  void add(KbFile f) {
    if (state.any((e) => e.url == f.url)) return; // takror emas
    state = [...state, f];
  }
  void removeAt(int i) {
    if (i < 0 || i >= state.length) return;
    final l = [...state]..removeAt(i);
    state = l;
  }
  void clear() => state = const [];
}

final kbAttachmentsProvider =
    StateNotifierProvider<KbAttachments, List<KbFile>>((_) => KbAttachments());
