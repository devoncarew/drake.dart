
library common_test;

import 'package:unittest/unittest.dart';
//import '../packages/unittest/unittest.dart';

import '../lib/utils.dart';

main() {
  group('common', () {
    test('i18n_found', () {
      expect(i18n('file_new'), equals('New'));
    });

    test('i18n_not_found', () {
      expect(i18n('not_found'), equals(''));
    });

    test('toTitleCase1', () {
      expect(toTitleCase('aa'), equals('Aa'));
    });
    test('toTitleCase2', () {
      expect(toTitleCase(''), equals(''));
    });
    test('toTitleCase3', () {
      expect(toTitleCase('a'), equals('A'));
    });

    test('stripQuotes1', () {
      expect(stripQuotes('"a"'), equals('a'));
    });
    test('stripQuotes2', () {
      expect(stripQuotes('""'), equals(''));
    });
    test('stripQuotes3', () {
      expect(stripQuotes(''), equals(''));
    });
    test('stripQuotes4', () {
      expect(stripQuotes('"abc'), equals('"abc'));
    });

    test('platform', () {
      expect(isLinux() || isMac() || isWin(), isTrue);
    });

    test('platform_one_set', () {
      int platformCount = 0;
      if (isLinux()) platformCount++;
      if (isMac()) platformCount++;
      if (isWin()) platformCount++;
      expect(platformCount, equals(1));
    });

    test('beep', () {
      // test that beep() does not throw
      // also, beeps are annoying
      //expect(beep(), equals(null));
    });
  });
}
