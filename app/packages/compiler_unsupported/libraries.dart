// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library libraries;

/**
 * A bit flag used by [LibraryInfo] indicating that a library is used by dart2js
 */
const int DART2JS_PLATFORM = 1;

/**
 * A bit flag used by [LibraryInfo] indicating that a library is used by the VM
 */
const int VM_PLATFORM = 2;

/**
 * Mapping of "dart:" library name (e.g. "core") to information about that library.
 * This information is structured such that Dart Editor can parse this file
 * and extract the necessary information without executing it
 * while other tools can access via execution.
 */
const Map<String, LibraryInfo> LIBRARIES = const {

  "async": const LibraryInfo(
      "async/async.dart",
      dart2jsPatchPath: "_internal/lib/async_patch.dart"),

  "chrome": const LibraryInfo(
      "chrome/dart2js/chrome_dart2js.dart",
      category: "Client"),

  "codec": const LibraryInfo(
      "codec/codec.dart"),

  "collection": const LibraryInfo(
      "collection/collection.dart",
      dart2jsPatchPath: "_internal/lib/collection_patch.dart"),

  "convert": const LibraryInfo(
      "convert/convert.dart"),

  "core": const LibraryInfo(
      "core/core.dart",
      dart2jsPatchPath: "_internal/lib/core_patch.dart"),

  "html": const LibraryInfo(
      "html/dartium/html_dartium.dart",
      category: "Client",
      dart2jsPath: "html/dart2js/html_dart2js.dart"),

  "html_common": const LibraryInfo(
      "html/html_common/html_common.dart",
      category: "Client",
      dart2jsPath: "html/html_common/html_common_dart2js.dart",
      documented: false,
      implementation: true),

  "indexed_db": const LibraryInfo(
      "indexed_db/dartium/indexed_db_dartium.dart",
      category: "Client",
      dart2jsPath: "indexed_db/dart2js/indexed_db_dart2js.dart"),

  "io": const LibraryInfo(
      "io/io.dart",
      category: "Server",
      dart2jsPatchPath: "_internal/lib/io_patch.dart"),

  "isolate": const LibraryInfo(
      "isolate/isolate.dart",
      dart2jsPatchPath: "_internal/lib/isolate_patch.dart"),

  "js": const LibraryInfo(
      "js/dartium/js_dartium.dart",
      category: "Client",
      dart2jsPath: "js/dart2js/js_dart2js.dart"),

  "json": const LibraryInfo(
      "json/json.dart",
      dart2jsPatchPath: "_internal/lib/json_patch.dart"),

  "math": const LibraryInfo(
      "math/math.dart",
      dart2jsPatchPath: "_internal/lib/math_patch.dart"),

  "mirrors": const LibraryInfo(
      "mirrors/mirrors.dart",
      dart2jsPatchPath: "_internal/lib/mirrors_patch.dart"),

  "nativewrappers": const LibraryInfo(
      "html/dartium/nativewrappers.dart",
      category: "Client",
      implementation: true,
      documented: false,
      platforms: VM_PLATFORM),

  "typed_data": const LibraryInfo(
      "typed_data/typed_data.dart",
      dart2jsPath: "typed_data/dart2js/typed_data_dart2js.dart"),

  "svg": const LibraryInfo(
        "svg/dartium/svg_dartium.dart",
        category: "Client",
        dart2jsPath: "svg/dart2js/svg_dart2js.dart"),

  "utf": const LibraryInfo(
      "utf/utf.dart"),

  "web_audio": const LibraryInfo(
        "web_audio/dartium/web_audio_dartium.dart",
        category: "Client",
        dart2jsPath: "web_audio/dart2js/web_audio_dart2js.dart"),

  "web_gl": const LibraryInfo(
        "web_gl/dartium/web_gl_dartium.dart",
        category: "Client",
        dart2jsPath: "web_gl/dart2js/web_gl_dart2js.dart"),

  "web_sql": const LibraryInfo(
        "web_sql/dartium/web_sql_dartium.dart",
        category: "Client",
        dart2jsPath: "web_sql/dart2js/web_sql_dart2js.dart"),

  "_collection-dev": const LibraryInfo(
      "_collection_dev/collection_dev.dart",
      category: "Internal",
      documented: false,
      dart2jsPatchPath:
          "_internal/lib/collection_dev_patch.dart"),

  "_js_helper": const LibraryInfo(
      "_internal/lib/js_helper.dart",
      category: "Internal",
      documented: false,
      platforms: DART2JS_PLATFORM),

  "_interceptors": const LibraryInfo(
      "_internal/lib/interceptors.dart",
      category: "Internal",
      documented: false,
      platforms: DART2JS_PLATFORM),

  "_foreign_helper": const LibraryInfo(
      "_internal/lib/foreign_helper.dart",
      category: "Internal",
      documented: false,
      platforms: DART2JS_PLATFORM),

  "_isolate_helper": const LibraryInfo(
      "_internal/lib/isolate_helper.dart",
      category: "Internal",
      documented: false,
      platforms: DART2JS_PLATFORM),

  "_js_mirrors": const LibraryInfo(
      "_internal/lib/js_mirrors.dart",
      category: "Internal",
      documented: false,
      platforms: DART2JS_PLATFORM),

  "_js_names": const LibraryInfo(
      "_internal/lib/js_names.dart",
      category: "Internal",
      documented: false,
      platforms: DART2JS_PLATFORM),
};

/**
 * Information about a "dart:" library.
 */
class LibraryInfo {

  /**
   * Path to the library's *.dart file relative to this file.
   */
  final String path;

  /**
   * The category in which the library should appear in the editor
   * (e.g. "Shared", "Client", "Server", ...).
   * If a category is not specified it defaults to "Shared".
   */
  final String category;

  /**
   * Path to the dart2js library's *.dart file relative to this file
   * or null if dart2js uses the common library path defined above.
   * Access using the [#getDart2JsPath()] method.
   */
  final String dart2jsPath;

  /**
   * Path to the dart2js library's patch file relative to this file
   * or null if no dart2js patch file associated with this library.
   * Access using the [#getDart2JsPatchPath()] method.
   */
  final String dart2jsPatchPath;

  /**
   * True if this library is documented and should be shown to the user.
   */
  final bool documented;

  /**
   * Bit flags indicating which platforms consume this library.
   * See [DART2JS_LIBRARY] and [VM_LIBRARY].
   */
  final int platforms;

  /**
   * True if the library contains implementation details for another library.
   * The implication is that these libraries are less commonly used
   * and that tools like Dart Editor should not show these libraries
   * in a list of all libraries unless the user specifically asks the tool to
   * do so.
   */
  final bool implementation;

  const LibraryInfo(this.path, {
                    this.category: "Shared",
                    this.dart2jsPath,
                    this.dart2jsPatchPath,
                    this.implementation: false,
                    this.documented: true,
                    this.platforms: DART2JS_PLATFORM | VM_PLATFORM});

  bool get isDart2jsLibrary => (platforms & DART2JS_PLATFORM) != 0;
  bool get isVmLibrary => (platforms & VM_PLATFORM) != 0;
}
