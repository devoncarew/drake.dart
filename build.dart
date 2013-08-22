
import "dart:io";

import "package:path/path.dart";

final List<String> WATCHED_FILES = [
  /*normalize("chrome-app/background.dart"),*/
  normalize("app/drake.dart")
];

bool get isWindows => Platform.operatingSystem == 'windows';
String get sdkBinPath => dirname(new Options().executable);
String get dart2jsPath => join(sdkBinPath, isWindows ? 'dart2js.bat' : 'dart2js');

/// This quick and dirty build script watches for changes to any .dart files
/// and re-compiles packy.dart using dart2js. The --disallow-unsafe-eval
/// flag causes dart2js to output CSP (and Chrome app) friendly code.
void main() {
  List<String> args = new Options().arguments;

  bool fullBuild = args.contains("--full");
  bool dartFilesChanged = args.any(
      (arg) => arg.startsWith("--changed=app") && arg.endsWith(".dart"));

  if (fullBuild || dartFilesChanged) {
    for (String path in WATCHED_FILES) {
      callDart2js(path);
    }
  }
}

void callDart2js(String path) {
  print("dart2js --disallow-unsafe-eval ${path}");

  String name = basename(path);
  String outPath = join(dirname(path), 'output', name);

  Process.run(
      dart2jsPath,
      ['--disallow-unsafe-eval', '-o${outPath}.js', path]
  ).then((result) {
    if (result.stdout.length > 0) {
      print("${result.stdout.replaceAll('\r\n', '\n')}");
    }

    if (result.exitCode != 0) {
      exit(result.exitCode);
    }
  });
}
