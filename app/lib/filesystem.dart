
library drake.filesystem;

import 'dart:async';

/**
 * The singleton instance of the FileSystemManager.
 */
final FileSystemManager fileSystemManager = new FileSystemManager();

// TODO: rename these classes to not conflict with html FileSystem

/**
 * The FileSystemManager class is used as a registry of all available file
 * systems.
 *
 * It is also able to serialize a FileSystemEntity into a string, and
 * de-serialize it back again. This is useful for persisting references to
 * files across sessions.
 */
class FileSystemManager {
  Map<String, FileSystem> _fileSystems = new Map<String, FileSystem>();

  /**
   * Register a new FileSystem with the FileSystemManager. This is generally
   * only called by file system implementations.
   */
  void register(FileSystem fileSytem) {
    _fileSystems[fileSytem.id] = fileSytem;
  }

  /**
   * Serialize a file system entity to a string.
   */
  String pickle(FileSystemEntity entity) {
    String entityPickle = entity.fileSystem.pickle(entity);

    return "${entity.fileSystem.id}:${entityPickle}";
  }

  // TODO: this needs to be made synchronous
  /**
   * Restore a file system entity from a string.
   */
  Future<FileSystemEntity> unpickle(String pickle) {
    int index = pickle.indexOf(':');

    if (index == -1) {
      return new Future.value(null);
    }

    String fsId = pickle.substring(0, index);
    String fileId = pickle.substring(index);

    FileSystem fs = _fileSystems[fsId];

    if (fs == null) {
      return new Future.value(null);
    }

    return fs.unpickle(fileId);
  }

  /**
   * Return the set of all available file systems.
   */
  Iterable<FileSystem> getFileSystems() {
    return _fileSystems.values;
  }
}

/**
 * An abstract file system.
 */
abstract class FileSystem {
  FileSystemFolder get root;

  String get id;

  String pickle(FileSystemEntity entity) {
    return entity.id;
  }

  Future<FileSystemEntity> unpickle(String pickle);
}

/**
 * A file system entity; either a file or a folder.
 */
abstract class FileSystemEntity {
  String get name;
  FileSystemFolder get parent;
  FileSystem get fileSystem;

  String get id;
}

/**
 * A representation of a file.
 */
abstract class FileSystemFile extends FileSystemEntity {
  bool get modifyable;

  Future<String> readContents();
}

/**
 * A representation of a folder.
 */
abstract class FileSystemFolder extends FileSystemEntity {
  Future<List<FileSystemEntity>> getChildren();

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
}
