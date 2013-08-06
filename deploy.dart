
import 'dart:io';
import 'dart:json' as json;

bool get isWindows => Platform.operatingSystem == 'windows';
Path get sdkBinPath => new Path(new Options().executable).directoryPath;
Path get sdkPath => sdkBinPath.join(new Path('..')).canonicalize();

void main() {
  // update the chrome app packages
  copyDirectory(
      directory('packages/analyzer_experimental'), 
      directory('app/packages/analyzer_experimental'));
  copyDirectory(directory('packages/browser'), directory('app/packages/browser'));
  copyDirectory(directory('packages/chrome'), directory('app/packages/chrome'));
  copyDirectory(directory('packages/js'), directory('app/packages/js'));
  copyDirectory(directory('packages/logging'), directory('app/packages/logging'));
  copyDirectory(directory('packages/meta'), directory('app/packages/meta'));
  copyDirectory(directory('packages/path'), directory('app/packages/path'));
  copyDirectory(directory('packages/stack_trace'), directory('app/packages/stack_trace'));
  copyDirectory(directory('packages/unittest'), directory('app/packages/unittest'));
  
  // copy over the sdk
  copyFile(sdkPath.join(new Path('version')), new Path('app/sdk'));
  copyDirectory(sdkPath.join(new Path('lib')), new Path('app/sdk/lib'));
  createFileListings(new Path('app/sdk'));
  
  // create application documentation
  // TODO:
}

void copyDirectory(Path srcDirPath, Path destDirPath, [bool quiet = false]) {
  if (!quiet) {
    print("copying ${srcDirPath} ==> ${destDirPath}");
  }

  Directory srcDir = new Directory.fromPath(srcDirPath);
  
  for (FileSystemEntity entity in srcDir.listSync()) {
    String name = new Path(entity.path).filename;
    
    if (entity is File) {
      copyFile(srcDirPath.join(new Path(name)), destDirPath);
    } else {
      copyDirectory(
          srcDirPath.join(new Path(name)),
          destDirPath.join(new Path(name)),
          true);
    }
  }
}

void copyFile(Path srcFilePath, Path destDirPath) {
  File srcFile = new File.fromPath(srcFilePath);
  File destFile = new File.fromPath(
      destDirPath.join(new Path(srcFilePath.filename)));
  
  new Directory.fromPath(destDirPath).createSync(recursive: true);
  
  destFile.writeAsBytesSync(srcFile.readAsBytesSync());
}

void createFileListings(Path directoryPath) {
  Directory dir = new Directory.fromPath(directoryPath);
  List<FileSystemEntity> entities = dir.listSync();
  
  List<String> names = new List<String>();
  
  for (FileSystemEntity entity in entities) {
    String name = new Path(entity.path).filename;
    
    if (name != 'files.json' && !name.startsWith('.')) {    
      if (entity is Directory) {
        names.add(name + '/');
        createFileListings(directoryPath.join(new Path(name)));
      } else {
        names.add(name);        
      }
    }
  }
  
  File jsonFile = new File.fromPath(directoryPath.join(new Path('files.json')));
  jsonFile.writeAsStringSync(json.stringify(names));
}

Path directory(String path) {
  return new Path(path);
}
