
library workspace_test;

import '../packages/unittest/unittest.dart';
import '../lib/workbench.dart';
import '../lib/workspace.dart';

Workspace get workspace => workbench.workspace;

main() {
  group('workspace', () {
    test('exists', () {
      expect(workspace, isNotNull);
    });
    
    test('parent is null', () {
      expect(workspace.parent, isNull);
    });
    
    test('name is null', () {
      expect(workspace.name, isNull);
    });
    
    test('has child list', () {
      expect(workspace.getChildren(), isNotNull);
    });
  });
}
