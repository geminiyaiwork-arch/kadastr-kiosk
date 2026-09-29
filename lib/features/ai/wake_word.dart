/// Uyg'otuvchi so'z = "ALOMAT" (2026-07-28, user talabi). Variantlar: Alomat / Alomatxon /
/// Olomat + Whisper xato-yozuvlari. Qo'shimchali shakllar (alomatga/alomatjon) startsWith
/// bilan ushlanadi.
const wakeSet = {
  'alomat', 'alomad', 'alomot', 'alamat', 'alamad', 'aloma', 'alomatxon', 'alomathon', 'alomatxan',
  'olomat', 'olomad', 'olomot', 'olomatxon', 'alamatxon', 'alomac', 'alomatga',
  // 1.9.51 (user): Whisper "Alomat"ni shunday ham yozadi — bular ham chaqiruv
  'salomat', 'salomatxon', 'salomad', 'ilomat', 'ilomatxon', 'ilomad', 'elomat', 'elomatxon', 'alomatjon', 'salomatjon',
  'саломат', 'саломатхон', 'иломат', 'иломатхон', 'эломат',
  'аломат', 'аломад', 'аломот', 'аламат', 'аломатхон', 'оломат', 'оломад', 'оломатхон', 'аломатхан',
};

final _wakeStem = RegExp(r'^(alomat|olomat|alamat|salomat|ilomat|elomat|аломат|оломат|аламат|саломат|иломат)');
// "alomatlar/alomatlari" = oddiy ot ("belgilar/simptomlar") — chaqiruv EMAS
// (atrofda "kasallik alomatlari" desa kiosk o'zidan uyg'onib ketmasin).
// "salomat bo'ling" — tilak; "salomatlik" — ot: chaqiruv EMAS
final _plural = RegExp(r'^(alomat|olomat|alamat|salomat|аломат|оломат|аламат|саломат)(lar|лар|lik|лик|lig)');

/// Bitta so'z (tinish belgisiz, kichik harf) chaqiruv so'zimi?
bool isWakeToken(String w) {
  if (w.isEmpty) return false;
  if (wakeSet.contains(w)) return true;
  // "alomat-xon" — defis bilan yozilsa birinchi qismi
  final dash = w.split(RegExp(r'[-—–]'));
  if (dash.length > 1 && dash.first.isNotEmpty && isWakeToken(dash.first)) return true;
  if (_plural.hasMatch(w)) return false;
  return _wakeStem.hasMatch(w);
}

const _tails = {'xon', 'hon', 'xan', 'han', 'xona', 'хон', 'хан', 'jon', 'жон'};

/// Birinchi [within] (standart 3) so'zda chaqiruv so'zini topadi. null = chaqiruv yo'q,
/// '' = faqat ism, aks holda — ismdan keyingi buyruq/savol (kichik harf, tinish belgisiz).
/// Zastavkada `within: 1` — gap ISM BILAN BOSHLANISHI shart.
String? stripWakeWord(String text, {int within = 3}) {
  final low = text.toLowerCase().replaceAll(RegExp(r"""['’`ʻʼ.,!?:;«»"“”„()]"""), '').trim();
  if (low.isEmpty) return null;
  final words = low.split(RegExp(r'\s+'));
  var wi = -1;
  var span = 1;
  for (var i = 0; i < words.length && i < within; i++) {
    final w = words[i];
    if (isWakeToken(w)) {
      // "salomat bo'ling" / "salomat bo'lsin" — tilak, chaqiruv EMAS (1.9.51)
      if (w.startsWith('salomat') || w.startsWith('саломат')) {
        final n = i + 1 < words.length ? words[i + 1] : '';
        if (n.startsWith('bol') || n.startsWith('бўл') || n.startsWith('бул')) continue;
      }
      wi = i;
      break;
    }
    // STT ismni ikkiga bo'lsa: "Alo mat" / "Ало мат"
    if ((w == 'alo' || w == 'ало') && i + 1 < words.length) {
      final n = words[i + 1];
      if (n == 'mat' || n == 'мат' || n.startsWith('matxon') || n.startsWith('матхон')) {
        wi = i;
        span = 2;
        break;
      }
    }
  }
  if (wi < 0) return null;
  // "Alomat xon" ikki so'z bo'lib eshitilsa — DAVOMI ('xon/hon/xan/jon') ham tashlanadi.
  var j = wi + span;
  while (j < words.length && _tails.contains(words[j])) {
    j++;
  }
  return words.sublist(j).join(' ').replaceAll(RegExp(r'^[\s,.:;!?"()\-—]+'), '').trim();
}
