
import 'dart:io';
import 'dart:json' as json;
import 'package:path/path.dart';
import "package:args/args.dart";

bool get isWindows => Platform.operatingSystem == 'windows';

String sdkPath;
const _argHelp = 'help';
const _argSdkHome = 'dart-sdk';

void main() {
  var parser = _getParser();
  var result = _getParserResults(parser);
  bool help = result[_argHelp];

  if (result.rest.isNotEmpty) {
    print('Unexpected arguments: ${result.rest}');
    printUsage(parser);
    exit(1);
    return;
  }

  if (help) {
    printUsage(parser);
    return;
  }

  sdkPath = result[_argSdkHome];

  if (sdkPath == null) {
    print("Missing arguments\n");
    printUsage(parser);
    exit(1);
    return;
  }

  // update the chrome app packages
  copyDirectory('packages/analyzer_experimental',
      'app/packages/analyzer_experimental');
  copyDirectory('packages/compiler_unsupported',
      'app/packages/compiler_unsupported');
  copyDirectory('packages/browser', 'app/packages/browser');
  copyDirectory('packages/chrome', 'app/packages/chrome');
  copyDirectory('packages/js', 'app/packages/js');
  copyDirectory('packages/logging', 'app/packages/logging');
  copyDirectory('packages/meta', 'app/packages/meta');
  copyDirectory('packages/path', 'app/packages/path');
  copyDirectory('packages/stack_trace', 'app/packages/stack_trace');
  copyDirectory('packages/unittest', 'app/packages/unittest');

  // copy over the sdk
  copyFile(join(sdkPath, 'version'), join('app', 'sdk'));
  copyDirectory(join(sdkPath, 'lib'), join('app', 'sdk', 'lib'));
  createFileListings(join('app', 'sdk'));

  // create application documentation
  // TODO:
}

void printUsage(parser) {
  print("""
deploy.dart --dart-sdk <SDK_HOME>
""");
  print(parser.getUsage());
}

ArgParser _getParser() => new ArgParser()
  ..addFlag(_argHelp, abbr: "h", help: "Display this information and exit", negatable: false)
  ..addOption(_argSdkHome, help: "Home Path of Dart SDK", defaultsTo: join(dirname(new Options().executable), ".."));

ArgResults _getParserResults(ArgParser parser) {
  final options = new Options();
  try {
    return parser.parse(options.arguments);
  } on FormatException catch (e) {
    print("Error parsing arguments:\n${e.message}\n");
    printUsage(parser);
    exit(1);
  }
}


void copyDirectory(String srcDirPath, String destDirPath,
                   [bool quiet = false]) {
  if (!quiet) {
    print("copying ${srcDirPath} ==> ${destDirPath}");
  }

  Directory srcDir = new Directory(srcDirPath);

  for (FileSystemEntity entity in srcDir.listSync()) {
    String name = entity.path;

    if (entity is File) {
      copyFile(name, destDirPath);
    } else {
      copyDirectory(
          name,
          join(destDirPath, basename(name)),
          true);
    }
  }
}

void copyFile(String srcFilePath, String destDirPath) {
  File srcFile = new File(srcFilePath);
  File destFile = new File(
      join(destDirPath, basename(srcFilePath)));

  //print("creating directory $destDirPath");
  new Directory(destDirPath).createSync(recursive: true);

  List<int> srcData = srcFile.readAsBytesSync();
  destFile.writeAsBytesSync(srcData);
}

void createFileListings(String directoryPath) {
  Directory dir = new Directory(directoryPath);
  List<FileSystemEntity> entities = dir.listSync();

  List<String> names = new List<String>();

  for (FileSystemEntity entity in entities) {
    String name = entity.path;

    if (name != 'files.json' && !name.startsWith('.')) {
      if (entity is Directory) {
        //names.add(name + '/');
        createFileListings(name);
      } else {
        names.add(name);
      }
    }
  }

  File jsonFile = new File(join(directoryPath, 'files.json'));
  jsonFile.writeAsStringSync(json.stringify(names));
}
