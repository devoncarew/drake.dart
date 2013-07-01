library java.io;

import "dart:io";

class JavaSystemIO {
  static Map<String, String> _properties = new Map();
  static String getProperty(String name) {
    {
      String value = _properties[name];
      if (value != null) {
        return value;
      }
    }
    if (name == 'os.name') {
      return Platform.operatingSystem;
    }
    if (name == 'line.separator') {
      if (Platform.operatingSystem == 'windows') {
        return '\r\n';
      }
      return '\n';
    }
    if (name == 'com.google.dart.sdk') {
      String value = Platform.environment['DART_SDK'];
      if (value != null) {
        _properties[name] = value;
        return value;
      }
    }
    if (name == 'com.google.dart.sdk') {
      String exec = new Options().executable;
      if (exec.length != 0) {
        String sdkPath;
        // may be "xcodebuild/ReleaseIA32/dart" with "dart-sdk" sibling
        {
          sdkPath = new Path(exec).directoryPath.append("dart-sdk").toNativePath();
          if (new Directory(sdkPath).existsSync()) {
            _properties[name] = sdkPath;
            return sdkPath;
          }
        }
        // probably be "dart-sdk/bin/dart"
        sdkPath = new Path(exec).directoryPath.directoryPath.toString();
        _properties[name] = sdkPath;
        return sdkPath;
      }
    }
    return null;
  }
  static String setProperty(String name, String value) {
    String oldValue = _properties[name];
    _properties[name] = value;
    return oldValue;
  }
  static String getenv(String name) => Platform.environment[name];
}

class JavaFile {
  static final String separator = Platform.pathSeparator;
  static final int separatorChar = Platform.pathSeparator.codeUnitAt(0);
  Path _path;
  JavaFile(String path) {
    this._path = new Path(path);
  }
  JavaFile.relative(JavaFile base, String child) {
    if (child.isEmpty) {
      this._path = base._path;
    } else {
      this._path = base._path.join(new Path(child));
    }
  }
  JavaFile.fromUri(Uri uri) : this(uri.path);
  int get hashCode => _path.hashCode;
  bool operator ==(other) {
    return other is JavaFile && other._path.toNativePath() == _path.toNativePath();
  }
  String getPath() => _path.toNativePath();
  String getName() => _path.filename;
  String getParent() {
    var result = _path.directoryPath.toNativePath();
    // "." or  "/" or  "C:\"
    if (result.length < 4) return null;
    return result;
  }
  JavaFile getParentFile() {
    var parent = getParent();
    if (parent == null) return null;
    return new JavaFile(parent);
  }
  String getAbsolutePath() => _path.canonicalize().toNativePath();
  String getCanonicalPath() => _path.canonicalize().toNativePath();
  JavaFile getAbsoluteFile() => new JavaFile(getAbsolutePath());
  JavaFile getCanonicalFile() => new JavaFile(getCanonicalPath());
  bool exists() {
    if (_newFile().existsSync()) {
      return true;
    }
    if (_newDirectory().existsSync()) {
      return true;
    }
    return false;
  }
  bool isDirectory() {
    return _newDirectory().existsSync();
  }
  Uri toURI() => new Uri(path: _path.toString());
  String readAsStringSync() => _newFile().readAsStringSync();
  int lastModified() => _newFile().lastModifiedSync().millisecondsSinceEpoch;
  List<JavaFile> listFiles() {
    List<JavaFile> files = [];
    List<FileSystemEntity> entities = _newDirectory().listSync();
    for (FileSystemEntity entity in entities) {
      files.add(new JavaFile(entity.path));
    }
    return files;
  }
  File _newFile() => new File.fromPath(_path);
  Directory _newDirectory() => new Directory.fromPath(_path);
}
