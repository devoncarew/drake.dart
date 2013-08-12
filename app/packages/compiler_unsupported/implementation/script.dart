// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart2js;

class Script {
  // TODO(kasperl): Once MockFile in tests/compiler/dart2js/parser_helper.dart
  // implements SourceFile, we should be able to type the [file] field as
  // such.
  final file;

  /**
   * The readable URI from which this script was loaded.
   *
   * See [LibraryLoader] for terminology on URIs.
   */
  final Uri uri;

  Script(this.uri, this.file);

  String get text => (file == null) ? null : file.text;
  String get name => (file == null) ? null : file.filename;
}
