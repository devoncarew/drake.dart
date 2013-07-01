
library preferences_test;

import 'dart:async';

import '../packages/unittest/unittest.dart';

import '../lib/preferences_chrome.dart';

main() {
  group('preferences.chrome', () {
    test('writeRead', () {
      chromePrefsLocal.setValue("foo1", "bar1");
      
      Future future = chromePrefsLocal.getValue("foo1").then((String val) {
        expect(val, equals("bar1"));
      });
      
      expect(future, completes); 
     });
  });    
}
