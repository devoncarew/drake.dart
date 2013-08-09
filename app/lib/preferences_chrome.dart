
library preferences_chrome;

import 'dart:async';

import '../packages/chrome/app.dart' as chrome;

import 'preferences.dart';

ChromePreferenceStore chromePrefsLocal = new ChromePreferenceStore(chrome.storage.local);
ChromePreferenceStore chromePrefsSync = new ChromePreferenceStore(chrome.storage.sync);

// TODO: listen for changes to the storage area

/**
 * A Chrome extension implementation of a [PreferenceStore].
 */
class ChromePreferenceStore extends PreferenceStore {
  StreamController<PreferenceEvent> streamController =
      new StreamController<PreferenceEvent>();

  chrome.StorageArea _storageArea;

  ChromePreferenceStore(chrome.StorageArea storageArea) {
    this._storageArea = storageArea;
  }

  Future<String> getValue(String key) {
    return _storageArea.get([key]).then((Map<String, String> map) {
      return new Future.value(map == null ? null : map[key]);
    });
  }

  Future<String> setValue(String key, String value) {
    Map<String, String> map = {};
    map[key] = value;

    return _storageArea.set(map).then((chrome.StorageArea _) {
      streamController.add(new PreferenceEvent(this, key, value));
      return new Future.value(value);
    });
  }

  void flush() {

  }

  Stream<PreferenceEvent> get onPreferenceChange => streamController.stream;
}
