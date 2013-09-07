
library drake.filesystem_chrome;

import 'dart:async';

import 'filesystem.dart';

final ChromeFileSystem chromeFileSystem = new ChromeFileSystem();

void registerChromeFileSystem() {
  fileSystemManager.register(chromeFileSystem);
}

class ChromeFileSystem extends FileSystem {

  FileSystemFolder get root {
    // TODO: implement

  }

  String get id {
    // TODO: implement

  }

  Future<FileSystemEntity> unpickle(String pickle) {
    // TODO: implement

  }
}
