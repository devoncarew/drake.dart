
library workbench_test;

import 'dart:async';
import 'dart:html';

import 'package:unittest/unittest.dart';
//import '../packages/unittest/unittest.dart';

import '../lib/workbench.dart';

main() {
  group('workbench', () {
    test('exists', () {
      expect(workbench, isNotNull);
    });

    test('active part events', () {
      Future future = workbench.onChange.take(2).toList().then((List<WorkbenchEvent> events) {
        WorkbenchEvent e = events.removeAt(0);
        expect(e, isNotNull);
        print(e);
        e = events.removeAt(0);
        expect(e, isNotNull);
        print(e);
      });

      MockEditorPart editor = new MockEditorPart(workbench);

      workbench.addEditor(editor);
      editor.close();

      expect(future, completes);
    });
  });
}

class MockEditorPart extends EditorPart {

  MockEditorPart(Workbench workbench) : super(workbench) {
    name = "MockEditorPart";
  }

  Element createContent(Element container) {
    LabelElement label = new LabelElement();
    label.text = 'foo';
    container.children.add(label);
    return label;
  }
}
