
library js_test;

import '../packages/unittest/unittest.dart';
import '../packages/js/js.dart' as js;

main() {
  jsInterop();
}

void jsInterop() {
  group('js_interop', () {
    // retain-release
    test('retainRelease1', () {
      js.Proxy proxy;

      proxy = js.array(["one", "two"]);
      js.retain(proxy);

      expect(proxy, isNotNull);

      js.release(proxy);

      expect(proxy, isNotNull);
    });
    test('retainRelease2', () {
      js.Proxy proxy;

      proxy = new js.Proxy((js.context as dynamic).Array);
      js.retain(proxy);

      expect(proxy, isNotNull);

      js.release(proxy);

      expect(proxy, isNotNull);
    });
    test('retainRelease3', () {
      js.Proxy proxy;

      proxy = new js.Proxy((js.context as dynamic).ace.EditSession, "", "ace/mode/dart");
      js.retain(proxy);

      expect(proxy, isNotNull);

      js.release(proxy);

      expect(proxy, isNotNull);
    });
  });
}
