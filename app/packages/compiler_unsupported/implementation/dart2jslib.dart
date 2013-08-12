// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js;

import 'dart:async';
import 'dart:collection' show Queue, LinkedHashMap;

import 'closure.dart' as closureMapping;
import 'dart_backend/dart_backend.dart' as dart_backend;
import 'dart_types.dart';
import 'elements/elements.dart';
import 'elements/modelx.dart'
    show ErroneousElementX,
         ClassElementX,
         CompilationUnitElementX,
         LibraryElementX,
         PrefixElementX,
         VoidElementX;
import 'js_backend/js_backend.dart' as js_backend;
import 'native_handler.dart' as native;
import 'scanner/scanner_implementation.dart';
import 'scanner/scannerlib.dart';
import 'ssa/ssa.dart';
import 'string_validator.dart';
import 'source_file.dart';
import 'tree/tree.dart';
import 'universe/universe.dart';
import 'util/characters.dart';
import 'util/util.dart';
import '../compiler.dart' as api;
import 'patch_parser.dart';
import 'types/types.dart' as ti;
import 'resolution/resolution.dart';
import 'js/js.dart' as js;
import 'deferred_load.dart' show DeferredLoadTask;
import 'types/container_tracer.dart' show ContainerTracer;

export 'resolution/resolution.dart' show TreeElements, TreeElementMapping;
export 'scanner/scannerlib.dart' show SourceString,
                                      isUserDefinableOperator,
                                      isUnaryOperator,
                                      isBinaryOperator,
                                      isTernaryOperator,
                                      isMinusOperator;
export 'universe/universe.dart' show Selector, TypedSelector;

part 'code_buffer.dart';
part 'compile_time_constants.dart';
part 'compiler.dart';
part 'constants.dart';
part 'constant_system.dart';
part 'constant_system_dart.dart';
part 'diagnostic_listener.dart';
part 'enqueue.dart';
part 'library_loader.dart';
part 'resolved_visitor.dart';
part 'script.dart';
part 'tree_validator.dart';
part 'typechecker.dart';
part 'warnings.dart';
part 'world.dart';
