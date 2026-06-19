import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr_kiosk/core/network/models.dart';

void main() {
  test('Stats parses live /stats shape + homeRow fallback', () {
    final s = Stats.fromJson({
      'tumanlar': 14,
      'arizalar': 13155,
      'auksion_yerlar': 19649,
      'maydon_ga': 1411.5,
      'kochmas_mulklar': 10758,
      'yer_uchastkalari': 19649,
      'xatlov_obyektlari': 13155,
    });
    expect(s.tumanlar, 14);
    expect(s.homeRow, [14, 10758, 19649, 13155]);
  });

  test('District parses live shape + city detection + phone mask', () {
    final d = District.fromJson({
      'name': 'Andijon tumani', 'type': 'tuman', 'head': '', 'engineer': '',
      'phone': '+998 (74) 22X-XX-XX', 'hours': '9:00 – 18:00', 'active': true,
      'auksion': 1730, 'arizalar': 831,
    });
    expect(d.name, 'Andijon tumani');
    expect(d.isCity, false);
    expect(d.phoneClean, ''); // masked phone hidden
    final city = District.fromJson({'name': 'Andijon shahri', 'type': 'shahar'});
    expect(city.isCity, true);
  });

  test('NewsItem parses multilingual title', () {
    final n = NewsItem.fromJson({
      'id': 1, 'date': '2026-05-24', 'uz': 'A', 'ru': 'Б', 'en': 'C', 'views': 5,
    });
    expect(n.titleFor('ru'), 'Б');
    expect(n.titleFor('xx'), 'A'); // falls back to uz
  });
}
