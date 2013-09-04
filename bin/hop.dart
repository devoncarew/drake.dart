
import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:hop/hop.dart';
import 'package:hop/hop_tasks.dart';

// TODO: FileSystemEntity needs a name property

// TODO: Directory needs a parent property, just like File (and it should be
// defined on FileSystemEntity)

Directory get sdkDir {
  // look for --dart-sdk on the command line
  List<String> args = new Options().arguments;
  if (args.contains('--dart-sdk')) {
    return new Directory(args[args.indexOf('dart-sdk') + 1]);
  }

  // look in env['DART_SDK']
  if (Platform.environment['DART_SDK'] != null) {
    return new Directory(Platform.environment['DART_SDK']);
  }

  // look relative to the dart executable
  // TODO: file a bug re: the path to the executable and the cwd
  return getParent(new File(Platform.executable).directory);
}

void main() {
  addTask('packages', copyPackagesTask());
  addTask('sdk', copySdkTask());
  addTask('compile', createDartCompilerTask([
      'app/drake.dart'],
      packageRoot: 'app/packages',
      allowUnsafeEval: false,
      verbose: false,
      suppressWarnings: true));
  addTask('archive', copyArchiveTask());
  addTask('info', copyInfoTask());

  runHop(paranoid: false);
}

/**
 * Copy the ./packages directory to the ./app/packages directory.
 */
Task copyPackagesTask() {
  // unittest needs stack_trace needs path
  // path, I think, causes the dart2js compiled size to blow up

  // copy from ./packages to ./app/packages
  List<String> packages = ['analyzer_experimental', 'compiler_unsupported',
      'chrome', 'meta', 'stack_trace', 'browser', 'js', 'unittest', 'logging',
      'path', 'unmodifiable_collection'];

  return new Task.async((TaskContext context) {
    for (String dirName in packages) {
      copyDirectory(
          joinDir(Directory.current, ['packages', dirName]),
          joinDir(Directory.current, ['app', 'packages', dirName]));
    }
    return new Future.value(true);
  }, description: 'copy from ./packages to ./app/packages');
}

/**
 * Create a copy of the current Dart SDK in app/sdk.
 */
Task copySdkTask() {
  return new Task.async((TaskContext context) {
    Directory sdk = null;

    if (context.arguments.rest.isEmpty) {
      sdk  = sdkDir;
    } else {
      sdk = new Directory(context.arguments.rest.first);
    }

    print("SDK location: ${sdk.path}");

    File versionFile = joinFile(sdk, ['version']);

    context.info('version ${versionFile.readAsStringSync().trim()}');

    copyFile(
        versionFile,
        joinDir(Directory.current, ['app', 'sdk']));
    copyDirectory(
        joinDir(sdk, ['lib']),
        joinDir(Directory.current, ['app', 'sdk', 'lib']));
    createFileListings(joinDir(Directory.current, ['app', 'sdk']));
    return new Future.value(true);
  }, description: 'copy the current Dart SDK into app/sdk',
  extendedArgs: [new TaskArgument('dart-sdk')]);
}

/**
 * Print out size infomation for the compiled output.
 */
Task copyInfoTask() {
  return new Task.async((TaskContext context) {
    File outputFile = joinFile(Directory.current, ['app', 'drake.dart.js']);

    context.info('${outputFile.path} is ${outputFile.lengthSync()} bytes');

    return new Future.value(true);
  }, description: 'copy the current Dart SDK into app/sdk');
}

/**
 * Zip the app/ directory into drake.zip.
 */
Task copyArchiveTask() {
  return new Task.async((TaskContext context) {
    Directory distDir = new Directory('dist');
    distDir.createSync();

    // zip drake.zip . -r -x .*
    ProcessResult result = Process.runSync(
        'zip',
        ['../dist/drake.zip', '.', '-r', '-x', '.*'],
        workingDirectory: 'app');

    return new Future.value(result.exitCode == 0);
  }, description: 'copy the current Dart SDK into app/sdk');
}

void createFileListings(Directory dir) {
  List<String> names = new List<String>();

  for (FileSystemEntity entity in dir.listSync()) {
    String name = getName(entity);

    if (name != 'files.json' && !name.startsWith('.')) {
      if (entity is Directory) {
        //names.add(name + '/');
        createFileListings(entity);
      } else {
        names.add(name);
      }
    }
  }

  File jsonFile = joinFile(dir, ['files.json']);
  jsonFile.writeAsStringSync(convert.JSON.encode(names));
}

void copyFile(File srcFile, Directory destDir) {
  File destFile = joinFile(destDir, [getName(srcFile)]);

  if (!destFile.existsSync() ||
      srcFile.lastModifiedSync() != destFile.lastModifiedSync()) {
    destDir.createSync(recursive: true);
    destFile.writeAsBytesSync(srcFile.readAsBytesSync());
  }
}

// These utils should all essentially be available in dart:io.

String getName(FileSystemEntity entity) {
  String name = entity.path;
  int index = name.lastIndexOf(Platform.pathSeparator);
  if (index != -1) {
    name = name.substring(index + 1);
  }
  return name;
}

String getBase(FileSystemEntity entity) {
  String name = entity.path;
  int index = name.lastIndexOf(Platform.pathSeparator);
  if (index != -1) {
    return name.substring(0, index);
  } else {
    return null;
  }
}

void copyDirectory(Directory srcDir, Directory destDir) {
  for (FileSystemEntity entity in srcDir.listSync()) {
    String name = getName(entity);

    if (entity is File) {
      copyFile(entity, destDir);
    } else {
      copyDirectory(entity, joinDir(destDir, [name]));
    }
  }
}

File joinFile(Directory dir, List<String> files) {
  String pathFragment = files.join(Platform.pathSeparator);
  return new File("${dir.path}${Platform.pathSeparator}${pathFragment}");
}

Directory joinDir(Directory dir, List<String> files) {
  String pathFragment = files.join(Platform.pathSeparator);
  return new Directory("${dir.path}${Platform.pathSeparator}${pathFragment}");
}

Directory getParent(Directory dir) {
  String base = getBase(dir);
  if (base == null) {
    return null;
  } else {
    return new Directory(base);
  }
}
