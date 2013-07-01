
library filesystem_sdk;

import 'dart:async';
import 'dart:html' as html;
import 'dart:json' as json;

import '../packages/chrome/chrome.dart' as chrome;

import 'utils.dart';
import 'filesystem.dart';


final SdkFileSystem sdkFileSystem = new SdkFileSystem();

void registerSdkFileSystem() {
  fileSystemManager.register(sdkFileSystem);
}

class SdkFileSystem extends FileSystem {
  _SdkFolder _root;
  
  SdkFileSystem() {
    _root = new _SdkFolder.createRoot(this, 'sdk');
  }
  
  FileSystemFolder get root => _root;
  
  String get id => "sdk";
  
  String pickle(FileSystemEntity entity) {
    return entity.id;
  }
  
  Future<FileSystemEntity> unpickle(String pickle) {
    List<String> paths = pickle.split('/');
    
    if (paths.isEmpty) {
      return new Future.value(null);
    }
    
    paths.removeAt(0);
    
    if (paths.isEmpty) {
      return new Future.value(root);
    } else {
      return _unpickle(root, paths);
    }
  }
  
  Future<FileSystemEntity> _unpickle(FileSystemFolder folder, List<String> paths) {
    String fileName = paths.removeAt(0);
    
    return folder.getChild(fileName).then((FileSystemEntity entity) {
      if (paths.isEmpty) {
        return new Future.value(entity);
      }
      
      if (entity is FileSystemFolder) {
        return _unpickle((entity as FileSystemFolder), paths);
      } else {
        return new Future.value(null);
      }
    });
  }
  
  Future<String> readContents(String path) {
    return html.HttpRequest.getString(chrome.Runtime.getURL(path));
  }
}

class _SdkEntity extends FileSystemEntity {
  _SdkFolder _parent;
  String _name;
  
  _SdkEntity(this._parent, this._name);
  
  String get name => _name;
  
  _SdkFolder get parent => _parent;
  
  SdkFileSystem get fileSystem => _parent.fileSystem;
  
  String get id => path;

  String get path {
    if (parent != null) {
      return '${parent.path}/${_name}';
    } else {
      return _name;
    }
  }
}

class _SdkFolder extends _SdkEntity implements FileSystemFolder {
  SdkFileSystem rootFs;
  List<FileSystemEntity> children;
  
  _SdkFolder(_SdkFolder parent, String name) : super(parent, name);
  
  _SdkFolder.createRoot(SdkFileSystem fs, String name) : super(null, name) {
    this.rootFs = fs;
  }
  
  SdkFileSystem get fileSystem {
    return rootFs != null ? rootFs : super.fileSystem;
  }
  
  Future<List<FileSystemEntity>> getChildren() {
    if (children != null) {
      return new Future.value(children);
    } else {
      Completer completer = new Completer();
      
      fileSystem.readContents(path + "/files.json").then((String value) {
        children = parseJson(value);
        completer.complete(children);
      }).catchError((_) {
        // TODO: ignore for now
        children = new List<FileSystemEntity>();
        completer.complete(children);
      });
      
      return completer.future;
    }
  }
  
  Future<FileSystemEntity> getChild(String name) {
    return getChildren().then((List<FileSystemEntity> children) {
      for (FileSystemEntity entity in children) {
        if (entity.name == name) {
          return new Future.value(entity);
        }
      }
      
      return new Future.value(null);
    });
  }
  
  List<FileSystemEntity> parseJson(String jsonText) {
    var list = json.parse(jsonText);
    List<FileSystemEntity> results = new List<FileSystemEntity>();
    
    for (String value in list) {
      if (value.endsWith('/')) {
        results.add(new _SdkFolder(this, value.substring(0, value.length - 1)));
      } else {
        results.add(new _SdkFile(this, value));
      }
    }
    
    return results;
  }
}

class _SdkFile extends _SdkEntity implements FileSystemFile {
  
  _SdkFile(_SdkFolder parent, String name) : super(parent, name);
  
  bool get modifyable => false;
  
  Future<String> readContents() {
    return fileSystem.readContents(path);
  }
}
