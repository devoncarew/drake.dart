
library analysis;

import 'dart:async';

import '../packages/analyzer_experimental/src/generated/ast.dart';
import '../packages/analyzer_experimental/src/generated/engine.dart';
import '../packages/analyzer_experimental/src/generated/error.dart';
import '../packages/analyzer_experimental/src/generated/sdk.dart';
import '../packages/analyzer_experimental/src/generated/source.dart';

export '../packages/analyzer_experimental/src/generated/ast.dart';
export '../packages/analyzer_experimental/src/generated/error.dart';

import '../packages/chrome/app.dart' as chrome;

import 'utils.dart';

DartSdk get dartSdk {
  // TODO: create a ChromeDartSdk

  return null;
}

String analysisLiteralToString(StringLiteral literal) {
  if (literal is SimpleStringLiteral) {
    return stripQuotes((literal as SimpleStringLiteral).value);
  } else {
    return literal.toString();
  }
}

Future<AnalysisResult> analysisParseString(String contents, [chrome.ChromeFileEntry file]) {
  Completer completer = new Completer();

  // TODO: do this work on a web worker

  AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();

//  context.sourceFactory = new SourceFactory.con2(
//      [new DartUriResolver(dartSdk)]);

  CompilationUnit unit;

  try {
    unit = context.parseCompilationUnit(
        new AnalysisStringSource(context, contents, file));
  } catch (e) {
    unit = new CompilationUnit();
  }

  AnalysisResult result = new AnalysisResult()
    ..ast = unit
    ..errors = unit.errors;

  completer.complete(result);

  return completer.future;
}

class AnalysisResult {
  List<AnalysisError> errors = [];
  CompilationUnit ast;
}

// TODO: implement this
class AnalysisStringSource extends Source {
  AnalysisContext _context;
  chrome.ChromeFileEntry file;
  String contents;

  AnalysisStringSource(this._context, this.contents, this.file) {

  }

  bool operator ==(Object object) {
    if (object is AnalysisStringSource) {
      AnalysisStringSource other = (object as AnalysisStringSource);

      return file == other.file || file.id == other.file.id;
    } else {
      return false;
    }
  }

  bool exists() => true;

  UriKind get uriKind => UriKind.FILE_URI;

  AnalysisContext get context => _context;

  void getContents(Source_ContentReceiver receiver) {
    receiver.accept2(contents, 0);
  }

  String get encoding => file.id;

  String get fullName => file == null ? null : file.name;

  int get modificationStamp => 0;

  String get shortName => file == null ? null : file.name;

  int get hashCode {
    String str = fullName;

    return str == null ? super.hashCode : str.hashCode;
  }

  bool get isInSystemLibrary => false;

  Source resolve(String uri) {
    // TODO:
    print("resolve ${uri}");
    null;
  }

  Source resolveRelative(Uri relativeUri) {
    // TODO:
    print("resolveRelative ${relativeUri}");
    null;
  }

}
