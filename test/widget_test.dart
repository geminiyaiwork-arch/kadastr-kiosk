import 'package:flutter_test/flutter_test.dart';

import 'package:kadastr_kiosk/core/i18n/strings.dart';

void main() {
  test('i18n has all three languages with matching service counts', () {
    expect(I18N.keys.toSet(), {'uz', 'ru', 'en'});
    for (final lang in I18N.values) {
      expect((lang['svc'] as List).length, 9);
      expect((lang['stats'] as List).length, 4);
    }
  });
}
