// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of scanner;

class ScannerTask extends CompilerTask {
  ScannerTask(Compiler compiler) : super(compiler);
  String get name => 'Scanner';

  void scanLibrary(LibraryElement library) {
    var compilationUnit = library.entryCompilationUnit;
    var canonicalUri = library.canonicalUri.toString();
    var resolvedUri = compilationUnit.script.uri.toString();
    if (canonicalUri == resolvedUri) {
      compiler.log("scanning library $canonicalUri");
    } else {
      compiler.log("scanning library $canonicalUri ($resolvedUri)");
    }
    scan(compilationUnit);
  }

  void scan(CompilationUnitElement compilationUnit) {
    measure(() {
      scanElements(compilationUnit);
    });
  }

  void scanElements(CompilationUnitElement compilationUnit) {
    Script script = compilationUnit.script;
    Token tokens = new StringScanner(script.text,
        includeComments: compiler.preserveComments).tokenize();
    if (compiler.preserveComments) {
      tokens = compiler.processAndStripComments(tokens);
    }
    compiler.dietParser.dietParse(compilationUnit, tokens);
  }
}

class DietParserTask extends CompilerTask {
  DietParserTask(Compiler compiler) : super(compiler);
  final String name = 'Diet Parser';

  dietParse(CompilationUnitElement compilationUnit, Token tokens) {
    measure(() {
      Function idGenerator = compiler.getNextFreeClassId;
      ElementListener listener =
          new ElementListener(compiler, compilationUnit, idGenerator);
      PartialParser parser = new PartialParser(listener);
      parser.parseUnit(tokens);
    });
  }
}
