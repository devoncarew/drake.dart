# Drake

[![Build Status](https://drone.io/github.com/devoncarew/drake.dart/status.png)](https://drone.io/github.com/devoncarew/drake.dart/latest)

A Chrome app based web development environment

Entry Point
-----------
The main entry point to the chrome app is app/manifest.json. It calls defines
the background script for the application (app/background.js). This script gets
invoked when the application starts. It open a new window, with the contents 
set to the app/drake.html file. This file sets up some minimal DOM structure,
and runs the app/drake.dart file.

Packages
--------
Chrome apps do not like symlinks. There's a chrome bug about this, but for now
symlinks are right out. We use pub and a pubspec.yaml to provision our
package dependencies (browser, js, unittest, and analyzer_experimental). We
then physically copy all the packages into the app/packages directory. This
is not a normal symlinked pub directory but has the same layout as one.

Dart vs JS mode
---------------
There are two ways of developing the app. You can run the Dart code in Chrome,
or run the dart2js output in Chrome.

Dart development:
  -edit drake.html, comment in the dart script and comment out the js script
  -right click on build.dart and choose 'Don't run build.dart'

JS development:
  -edit drake.html, and swap the Dart scrip for the JS one
  -make sure build.dart is enbaled. On every file change, it'll re-build the app

Deployment
----------
To deploy, make sure you are set up in the JS development mode (see above). Run
the app, then choose Tools > Extensions from the chrome menu. Check 
'Developer mode' and select 'Pack extension...'. 

Ace
---
All the JS for Ace is in app/ace; the dart wrapper library for it is in
app/lib/ace.dart.

Bootstrap
---
All the CSS for Bootstrap is in app/bootstrap; the Dart wrapper library for 
their components is in app/lib/bootstrap.dart.

Lib
---
All the Dart code for the application (modulo the drake.dart entry point)
lives in the app/lib directory. We're following a 1 library == 1 file
philosophy. 

Output
------
The output from dart2js lives in the app/output directory
(app/output/drake.dart.js).

SDK
---
A copy of the sdk lives in app/sdk. This is created by running the deploy.dart 
script. It copies all the sdk libraries into the sdk directory and creates
a list of files for each directory (files.json). This structure allows us to
access and reflect on the sdk contents in the context of the chrome app. We
essentially create a read-only filesystem for the sdk; the directory listings
are provided by the files.json fils, and the file contents are retrieved using
XHR.

Tests
-----
All the tests live in app/test. These are standard dart unit tests. They are all
built into the application, and can be run from the Tools > Tests menu item.
Generally, one library under test == 1 test file, and they should all be
referenced from alltests.dart.
