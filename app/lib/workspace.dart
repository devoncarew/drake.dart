// A resource workspace implementation.

library workspace;

import 'dart:async';

import 'filesystem.dart';
import 'preferences.dart';

/**
 * This top-level entity can contain files and folders. The files that it
 * contains are loose files; they do not have parent folders. The folders
 * it contains are all top-level folders.
 */
class Workspace implements Container {
  List<Resource> _children = [];
  PreferenceStore _store;
  
  Workspace(PreferenceStore preferenceStore) {
    this._store = preferenceStore;
  }
  
  String get name => null;
  
  Container get parent => null;
  
  Future<Workspace> initialize() {
    // TODO:
    
//    return _store.getValue('resources').then((String str) {
//      if (str != null) {
//        for (String path in str.split(';')) {
//          fileSystemManager.unpickle(pickle)
//        }
//      }
      
      return new Future.value(this);
//    });
  }
  
  // TODO: use a future
  Resource link(FileSystemEntity entity) {
    List<Resource> children = getChildren();
      
    if (entity is FileSystemFile) {
      children.add(new File(this, entity));
    } else {
      children.add(new Folder(this, entity));
    }
    
    _flush();
  }
  
  // TODO: use a future
  void unlink(Resource resource) {
    List<Resource> children = getChildren();

    children.remove(resource);
    
    _flush();
  }
  
  List<Resource> getChildren() {
    if (_children != null) {
      return _children;
    } else {
//      return _store.getValue("resources").then((String value) {
//        _children = new List<Resource>();
//        
//        if (value == null) {
//          return new Future.value(_children);
//        }
//        
//        return Future.forEach(value.split(';'), (String str) {
//          return fileSystemManager.unpickle(str).then((FileSystemEntity entity) {
//            if (entity is FileSystemFile) {
//              _children.add(new File(this, entity));
//            } else {
//              _children.add(new Folder(this, entity));
//            }            
//          });
//        }).then((_) {
//          return new Future.value(_children);
//        });
//      });
      // TODO:
      _children = [];
      return _children;
    }
  }
  
  void _flush() {
    String token = _children.map((Resource r) {
      return fileSystemManager.pickle(r._fileEntry);
    }).join(';');
    
    _store.setValue("resources", token);
  }
}

abstract class Container extends Resource {
  List<Resource> _children;
  
  Container(Container parent, FileSystemEntity entry) : super(parent, entry);
  
  List<Resource> getChildren() {
    if (_children != null) {
      return _children;
    } else {
//      FileSystemFolder folder = _fileEntry as FileSystemFolder;
//      
//      return folder.getChildren().then((List<FileSystemEntity> files) {
//        _children = new List<Resource>();
//        
//        for (FileSystemEntity file in files) {
//          if (file is FileSystemFile) {
//            _children.add(new File(this, file));
//          } else {
//            _children.add(new Folder(this, file));
//          }
//        }
//        
//        return new Future.value(_children);
//      });
      _children = [];
      return _children;
    }
  }
}

abstract class Resource {
  Container _parent;
  FileSystemEntity _fileEntry;
  
  Resource(this._parent, this._fileEntry);
  
  String get name => _fileEntry.name;
  
  Container get parent => _parent;
  
  /**
   * Returns the top-level folder. This can return null for loose files.
   */
  Folder get topLevelFolder {
    Container p = parent;
    
    while (p != null) {
      if (p is Folder && ((p as Folder).isTopLevel)) {
        return (p as Folder);
      }
      
      p = p.parent;
    }
  }
}

// TODO:
class Folder extends Container {
  
  Folder(Container parent, FileSystemEntity entry) : super(parent, entry);
  
  bool get isTopLevel => parent is Workspace;
  
}

// TODO:
class File extends Resource {

  File(Container parent, FileSystemEntity entry) : super(parent, entry);
  
  List<Marker> getMarkers() {
    // TODO:
    
  }
  
}

class Marker {
  File _file;
  String _message;
  
  Marker(this._file, this._message);
  
  File get file => _file;
  
  String get message => _message;  
}
