
library filesystem_sdk_test;

import 'dart:async';

import '../packages/unittest/unittest.dart';

import '../lib/filesystem.dart';
import '../lib/filesystem_sdk.dart';

main() {
  basicTests();
}

void basicTests() {
  group('filesystem_sdk', () {
    test('exists', () {
      expect(sdkFileSystem, isNotNull);
    });
    
    test('rootExists', () {
      expect(sdkFileSystem.root, isNotNull);
    });
    
    test('readVersion', () {
      Future<String> versionContents = sdkFileSystem.readContents('sdk/version');
      
      // 0.5.0.1_r21823
      versionContents.then((String str) {
        str = str.trim();
        
        expect(str.length, lessThan(100));
        expect(str, startsWith('0.'));
        expect(str, stringContainsInOrder(['_r']));
      });
      
      expect(versionContents, completes);
    });
    
    test('readDirectory', () {
      Future<List<FileSystemEntity>> future = sdkFileSystem.root.getChildren();

      future.then((List<FileSystemEntity> children) {
        expect(children.length, equals(2));
        
        FileSystemFolder folder = children[0];
        expect(folder.name, equals("lib"));
        expect(folder.id, isNotNull);
        expect(folder.parent, equals(sdkFileSystem.root));
        expect(folder.fileSystem, equals(sdkFileSystem));
        
        FileSystemFile file = children[1];        
        expect(file.name, equals("version"));
        expect(file.id, isNotNull);
        expect(file.parent, equals(sdkFileSystem.root));
        expect(file.fileSystem, equals(sdkFileSystem));
        expect(file.modifyable, equals(false));
      });
      
      expect(future, completes);
    });
    
    test('pickleFile', () {
      Future future = sdkFileSystem.unpickle("sdk/version").then((FileSystemFile file) {
        expect(file, isNotNull);
        expect(file is FileSystemFile, true);
        expect(file.name, equals("version"));
        expect(sdkFileSystem.pickle(file), equals("sdk/version"));
      });
      
      expect(future, completes);
    });
    
    test('pickleDirectory', () {
      Future future = sdkFileSystem.unpickle("sdk/lib").then((FileSystemFile file) {
        expect(file, isNotNull);
        expect(file is FileSystemFolder, true);
        expect(file.name, equals("lib"));        
        expect(sdkFileSystem.pickle(file), equals("sdk/lib"));
      });
      
      expect(future, completes);
    });
  });
}
