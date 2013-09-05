
library analysis_test;

import 'dart:async';

import 'package:unittest/unittest.dart';
//import '../packages/unittest/unittest.dart';

import '../lib/analysis.dart';

main() {
  group('analysis', () {
    test('createAST', () {
      String contents = "void main() { print('foo'); }";

      Future future = analysisParseString(contents).then((AnalysisResult result) {
        expect(result.ast, isNotNull);
        expect(result.errors, isEmpty);
      });

      expect(future, completes);
    });
  });
}
