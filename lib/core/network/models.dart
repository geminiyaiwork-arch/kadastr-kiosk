// API models (from live /stats, /districts, /news shapes).

num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _s(dynamic v) => v == null ? '' : '$v';

class Stats {
  final int tumanlar, arizalar, auksionYerlar, kochmasMulklar, yerUchastkalari, xatlovObyektlari;
  final double maydonGa;
  const Stats({
    required this.tumanlar,
    required this.arizalar,
    required this.auksionYerlar,
    required this.kochmasMulklar,
    required this.yerUchastkalari,
    required this.xatlovObyektlari,
    required this.maydonGa,
  });

  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
        tumanlar: _n(j['tumanlar']).toInt(),
        arizalar: _n(j['arizalar']).toInt(),
        auksionYerlar: _n(j['auksion_yerlar']).toInt(),
        kochmasMulklar: _n(j['kochmas_mulklar']).toInt(),
        yerUchastkalari: _n(j['yer_uchastkalari']).toInt(),
        xatlovObyektlari: _n(j['xatlov_obyektlari']).toInt(),
        maydonGa: _n(j['maydon_ga']).toDouble(),
      );

  /// Home stats panel values (web fallback logic): districts, real-estate,
  /// land-plots, inventory-objects.
  List<int> get homeRow => [
        tumanlar,
        kochmasMulklar != 0 ? kochmasMulklar : arizalar,
        yerUchastkalari != 0 ? yerUchastkalari : auksionYerlar,
        xatlovObyektlari != 0 ? xatlovObyektlari : arizalar,
      ];

  static const empty = Stats(
    tumanlar: 16, arizalar: 0, auksionYerlar: 0, kochmasMulklar: 0,
    yerUchastkalari: 0, xatlovObyektlari: 0, maydonGa: 0,
  );
}

class District {
  final String name, type, head, engineer, phone, hours;
  final bool active;
  final int auksion, arizalar;
  const District({
    required this.name,
    required this.type,
    required this.head,
    required this.engineer,
    required this.phone,
    required this.hours,
    required this.active,
    required this.auksion,
    required this.arizalar,
  });

  bool get isCity => type == 'shahar' || RegExp(r'sh\.?$|shahri$', caseSensitive: false).hasMatch(name);
  String get phoneClean => RegExp(r'X-XX-XX').hasMatch(phone) ? '' : phone;

  factory District.fromJson(Map<String, dynamic> j) => District(
        name: _s(j['name']),
        type: _s(j['type']),
        head: _s(j['head']),
        engineer: _s(j['engineer']),
        phone: _s(j['phone']),
        hours: _s(j['hours']),
        active: j['active'] != false,
        auksion: _n(j['auksion']).toInt(),
        arizalar: _n(j['arizalar']).toInt(),
      );
}

class SocialLink {
  final String name, url;
  const SocialLink({required this.name, required this.url});
  factory SocialLink.fromJson(Map<String, dynamic> j) =>
      SocialLink(name: _s(j['name']), url: _s(j['url']));
}

class PhoneEntry {
  final String name, dept, number;
  const PhoneEntry({required this.name, required this.dept, required this.number});
  factory PhoneEntry.fromJson(Map<String, dynamic> j) => PhoneEntry(
        name: _s(j['name']), dept: _s(j['dept']), number: _s(j['number']));
}

class ReceptionManager {
  final int id;
  final String name, position, days, hours;
  const ReceptionManager({
    required this.id, required this.name, required this.position,
    required this.days, required this.hours,
  });
  factory ReceptionManager.fromJson(Map<String, dynamic> j) => ReceptionManager(
        id: _n(j['id']).toInt(), name: _s(j['name']), position: _s(j['position']),
        days: _s(j['days']), hours: _s(j['hours']));
}

class DocItem {
  final String name, fee, term;
  const DocItem({required this.name, required this.fee, required this.term});
  factory DocItem.fromJson(Map<String, dynamic> j) => DocItem(
        name: _s(j['name']), fee: _s(j['fee']), term: _s(j['term']));
}

class IllegalDistrict {
  final String name, display;
  final int count;
  final bool city;
  const IllegalDistrict({required this.name, required this.display, required this.count, required this.city});
  factory IllegalDistrict.fromJson(Map<String, dynamic> j) => IllegalDistrict(
        name: _s(j['name']),
        display: _s(j['display'].toString().isEmpty ? j['name'] : j['display']),
        count: _n(j['count']).toInt(),
        city: j['city'] == true,
      );
}

class IllegalSummary {
  final int total;
  final List<IllegalDistrict> districts;
  const IllegalSummary({required this.total, required this.districts});
  factory IllegalSummary.fromJson(Map<String, dynamic> j) => IllegalSummary(
        total: _n(j['total']).toInt(),
        districts: (j['districts'] as List? ?? [])
            .map((e) => IllegalDistrict.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class IllegalRecord {
  final String fio, jshshir, passport, viloyat, tuman, tumanFull, mahalla, area, tur, modda, status, inner, kadastr, sana;
  const IllegalRecord({
    required this.fio, required this.jshshir, required this.passport, required this.viloyat,
    required this.tuman, required this.tumanFull, required this.mahalla, required this.area,
    required this.tur, required this.modda, required this.status, required this.inner,
    required this.kadastr, required this.sana,
  });
  factory IllegalRecord.fromJson(Map<String, dynamic> j) => IllegalRecord(
        fio: _s(j['fio']), jshshir: _s(j['jshshir']), passport: _s(j['passport']),
        viloyat: _s(j['viloyat']), tuman: _s(j['tuman']), tumanFull: _s(j['tuman_full']),
        mahalla: _s(j['mahalla']), area: _s(j['area']), tur: _s(j['tur']), modda: _s(j['modda']),
        status: _s(j['status']), inner: _s(j['inner']), kadastr: _s(j['kadastr']), sana: _s(j['sana']));
}

class AvatarConfig {
  final bool enabled;
  final String file, type, voice;
  final int ts;
  const AvatarConfig({this.enabled = false, this.file = '', this.type = '', this.voice = 'madina', this.ts = 0});
  factory AvatarConfig.fromJson(Map<String, dynamic> j) => AvatarConfig(
        enabled: j['enabled'] == true,
        file: _s(j['file']), type: _s(j['type']),
        voice: _s(j['voice'].toString().isEmpty ? 'madina' : j['voice']),
        ts: _n(j['ts']).toInt(),
      );
  /// gender key for /tts/synthesize&voice= (sardor/male => male else female)
  bool get male => RegExp(r'sardor|male|erkak|^m$', caseSensitive: false).hasMatch(voice);
}

class NewsItem {
  final int id;
  final String date;
  final Map<String, String> title; // uz/ru/en
  final String? media;
  final String? mediaType;
  final int views;
  const NewsItem({
    required this.id,
    required this.date,
    required this.title,
    required this.views,
    this.media,
    this.mediaType,
  });

  String titleFor(String lang) => title[lang] ?? title['uz'] ?? '';

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        id: _n(j['id']).toInt(),
        date: _s(j['date'].toString().isEmpty ? j['d'] : j['date']),
        title: {
          'uz': _s(j['uz']),
          'ru': _s(j['ru']),
          'en': _s(j['en']),
        },
        media: j['media'] == null ? null : _s(j['media']),
        mediaType: j['mediaType'] == null ? null : _s(j['mediaType']),
        views: _n(j['views']).toInt(),
      );
}
