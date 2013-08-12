// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:json';

// TODO(ahe): Should be dart:mirrors.
import '../../implementation/mirrors/mirrors.dart';

import '../libraries.dart'
    show LIBRARIES, LibraryInfo;

import '../../implementation/mirrors/dart2js_mirror.dart'
    show analyze, BackDoor;

import '../../implementation/filenames.dart';
import '../../implementation/source_file.dart';
import '../../implementation/source_file_provider.dart';
import '../../implementation/util/uri_extras.dart';

const DART2JS = '../../implementation/dart2js.dart';
const DART2JS_MIRROR = '../../implementation/mirrors/dart2js_mirror.dart';
const SDK_ROOT = '../../../../../';

bool isPublicDart2jsLibrary(String name) {
  return !name.startsWith('_') && LIBRARIES[name].isDart2jsLibrary;
}

var handler;
RandomAccessFile output;
Uri outputUri;
Uri sdkRoot;

main() {
  mainWithOptions(new Options());
}

mainWithOptions(Options options) {
  handler = new FormattingDiagnosticHandler()
      ..throwOnError = true;

  outputUri =
      handler.provider.cwd.resolve(nativeToUriPath(options.arguments.first));
  output = new File(options.arguments.first).openSync(mode: FileMode.WRITE);

  Uri myLocation =
      handler.provider.cwd.resolve(nativeToUriPath(options.script));

  sdkRoot = myLocation.resolve(SDK_ROOT).resolve('../');

  // Get the names of public dart2js libraries.
  Iterable<String> names = LIBRARIES.keys.where(isPublicDart2jsLibrary);

  // Turn the names into uris by prepending dart: to them.
  List<Uri> uris = names.map((String name) => Uri.parse('dart:$name')).toList();

  analyze(uris, myLocation.resolve(SDK_ROOT), null, handler.provider, handler)
      .then(jsonify);
}

jsonify(MirrorSystem mirrors) {
  var map = {};

  mirrors.libraries.forEach((_, LibraryMirror library) {
    BackDoor.compilationUnitsOf(library).forEach((compilationUnit) {
      Uri uri = compilationUnit.uri;
      String filename = relativize(sdkRoot, uri, false);
      SourceFile file = handler.provider.sourceFiles['$uri'];
      map['sdk:/$filename'] = file.text;
    });
  });

  LIBRARIES.forEach((name, info) {
    var patch = info.dart2jsPatchPath;
    if (patch != null) {
      Uri uri = sdkRoot.resolve('sdk/lib/$patch');
      String filename = relativize(sdkRoot, uri, false);
      SourceFile file = handler.provider.sourceFiles['$uri'];
      map['sdk:/$filename'] = file.text;
    }
  });

  output.writeStringSync('''
// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// DO NOT EDIT.
// This file is generated by jsonify.dart.

library dart.sdk_sources;

const Map<String, String> SDK_SOURCES = const <String, String>''');
  output.writeStringSync(stringify(map).replaceAll(r'$', r'\$'));
  output.writeStringSync(';\n');
  output.closeSync();
}
