
library alltests;

import 'package:unittest/unittest.dart';
//import '../packages/unittest/unittest.dart';

import '../lib/workbench.dart';

import 'ace_test.dart' as ace_test;
import 'analysis_test.dart' as analysis_test;
import 'chrome_socket_test.dart' as chrome_socket_test;
import 'common_test.dart' as common_test;
import 'filesystem_sdk_test.dart' as filesystem_sdk_test;
import 'jobs_test.dart' as jobs_test;
import 'js_test.dart' as js_test;
import 'preferences_test.dart' as preferences_test;
import 'workbench_test.dart' as workbench_test;
import 'workspace_test.dart' as workspace_test;

bool _testsDefined = false;

main() {
  ace_test.main();
  analysis_test.main();
  chrome_socket_test.main();
  common_test.main();
  filesystem_sdk_test.main();
  jobs_test.main();
  js_test.main();
  preferences_test.main();
  workbench_test.main();
  workspace_test.main();
}

void runTests(Workbench workbench) {
  if (_testsDefined) {
    rerunTests();
  } else {
    unittestConfiguration = new WorkbenchTestConfiguration(workbench);

    main();

    _testsDefined = true;
  }
}

class WorkbenchTestConfiguration implements Configuration {
  Workbench workbench;

  WorkbenchTestConfiguration(this.workbench);

  bool get autoStart => false;

  Duration timeout = const Duration(seconds: 5);

  void onInit() {

  }

  void onStart() {

  }

  void onDone(bool success) {

  }

  void onLogMessage(TestCase testCase, String message) {
    workbench.console.append(message);
  }

  void onTestStart(TestCase testCase) {

  }

  void onTestResultChanged(TestCase testCase) {

  }

  void onTestResult(TestCase testCase) {

  }

  void onSummary(int passed, int failed, int errors,
                 List<TestCase> results, String uncaughtError) {
    for (TestCase test in results) {
      print('${test.result}: ${test.description}');
      workbench.console.append('${test.result}: ${test.description}');

      if (test.message != '') {
        print(test.message);
        workbench.console.append(test.message);
      }

      if (test.stackTrace != null && test.stackTrace != '') {
        workbench.console.append(indent(test.stackTrace.toString()));
      }
    }

    workbench.messageArea.clearAlerts();

    if (passed == 0 && failed == 0 && errors == 0 && uncaughtError == null) {
      workbench.messageArea.showWarningAlert("Tests", 'No tests found.');
    } else if (failed == 0 && errors == 0 && uncaughtError == null) {
      workbench.messageArea.showSuccessAlert(
          "Tests", 'All $passed tests passed!');
    } else {
      if (uncaughtError != null) {
        workbench.messageArea.showErrorAlert(
            "Tests", 'Top-level uncaught error: $uncaughtError');
      }

      workbench.messageArea.showErrorAlert(
          "Tests", '$passed PASSED, $failed FAILED, $errors ERRORS');
    }
  }

  String indent(String str) {
    return str.split("\n").map((line) => "  $line").join("\n");
  }

}
