
library ace_test;

import 'package:unittest/unittest.dart';
//import '../packages/unittest/unittest.dart';

import '../lib/ace.dart';
import '../lib/workbench.dart';

AceEditor get editor => workbench.aceEditor;

main() {
  group('ace', () {
    test('getModes', () {
      expect(editor.getModes().length, greaterThan(1));
    });
    test('getTheme', () {
      expect(editor.getTheme(), isNotNull);
    });
    test('getThemes', () {
      expect(editor.getThemes().length, greaterThan(1));
    });
  });
}
