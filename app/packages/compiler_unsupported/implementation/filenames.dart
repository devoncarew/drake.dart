// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library filenames;

import 'dart:io';

// TODO(ahe): This library should be replaced by a general
// path-munging library.
//
// See also:
// http://blogs.msdn.com/b/ie/archive/2006/12/06/file-uris-in-windows.aspx

String nativeToUriPath(String filename) {
  return new Path(filename).toString();
}

String uriPathToNative(String path) {
  return new Path(path).toNativePath();
}

final Uri currentDirectory = new Uri(
    scheme: 'file',
    path: appendSlash(nativeToUriPath(new File('.').fullPathSync())));

String appendSlash(String path) => path.endsWith('/') ? path : '$path/';
