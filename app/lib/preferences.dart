// Preferences.

library preferences;

import 'dart:async';

/**
 * A persistent preference mechanism.
 */
abstract class PreferenceStore {
  /**
   * Get the value for the given key. The value is returned as a [Future].
   */
  Future<String> getValue(String key);
  
  /**
   * Set the value for the given key. The returned [Future] has the same value
   * as [value] on success.
   */
  Future<String> setValue(String key, String value);
  
  /**
   * Flush any unsaved changes to this [PreferenceStore]. Implementations may
   * flush on each call to [setValue] (i.e. [flush] may be a no-op).
   */
  void flush();
  
  Stream<PreferenceEvent> get onPreferenceChange;
}

/**
 * A event class for preference changes.
 */
class PreferenceEvent {
  final PreferenceStore store;
  final String key;
  final String value;
  
  PreferenceEvent(this.store, this.key, this.value);
}
