
library drake_test;

import 'drake.dart' as drake;
import 'lib/bootstrap.dart';
import 'test/alltests.dart' as testing;

void main() {
  DrakeTest app = new DrakeTest();
}

class DrakeTest extends drake.Drake {

  DrakeTest();

  void createMenubar() {
    super.createMenubar();

    BMenubar menubar = workbench.titleArea.menubar;

    BMenu toolsMenu = menubar.getMenu('Tools');
    toolsMenu.addSeparator();
    toolsMenu.add(new BMenuItem('Run Tests', handleRunTests));
  }

  void handleRunTests(var event) {
    testing.runTests(workbench);
  }

}
