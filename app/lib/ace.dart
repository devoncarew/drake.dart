
library ace;

import 'dart:async';
import 'dart:html';

import '../packages/js/js.dart' as js;

import 'bootstrap.dart';
import 'utils.dart';

dynamic get _context => js.context;
dynamic get _ace => _context.ace;

class AceEditor {
  DivElement _aceContainer;
  Element _otherContainer;
  AceEditSession _session;

  var _aceEditor;

  AceEditor(BTabContainer tabContainer) {
    _otherContainer = tabContainer.content;

    _aceContainer = tabContainer.editorContent;
    _aceContainer.style.display = 'none';

    js.scoped(() {
      _aceEditor = _ace.edit(_aceContainer);
      _aceEditor.setTheme("ace/theme/textmate");
      _aceEditor.getSession().setMode("ace/mode/dart");

      js.retain(_aceEditor);
    });
  }

  void show() {
    _otherContainer.style.display = 'none';
    _aceContainer.style.display = 'block';
  }

  void hide() {
    _aceContainer.style.display = 'none';
    _otherContainer.style.display = 'block';
  }

  void focus() => _aceEditor.focus();

  void resize() => _aceEditor.resize();

  AceEditSession setSession(AceEditSession session) {
    _session = session;

    _aceEditor.setSession(_session.proxy);
  }

  /**
   * Moves the cursor to the specified line number, and also into the indiciated
   * column.
   */
  void gotoLine(int lineNumber, int column, bool animate) {
    _aceEditor.gotoLine(lineNumber, column, animate);
  }

  /**
   * Moves the editor to the specified row.
   *
   * (possibly 0-based?)
   */
  void scrollToRow(int row) {
    _aceEditor.scrollToRow(row);
  }

  /**
   * Returns true if the print margin is being shown.
   */
  bool getShowPrintMargin() {
    return _aceEditor.getShowPrintMargin();
  }

  /**
   * Returns the path of the current theme.
   */
  String getTheme() {
    return _aceEditor.getTheme();
  }

  /**
   * Returns true if the editor is set to read-only mode.
   */
  bool getReadOnly() {
    return _aceEditor.getReadOnly();
  }

  /**
   * Moves the cursor to the start of the current file. Note that this does
   * de-select the current selection.
   */
  void navigateFileStart() {
    _aceEditor.navigateFileStart();
  }

  /**
   * If readOnly is true, then the editor is set to read-only mode, and none of
   * the content can change.
   */
  void setReadOnly(bool readOnly) {
    _aceEditor.setReadOnly(readOnly);
  }

  /**
   * If showPrintMargin is set to true, the print margin is shown in the editor.
   */
  void setShowPrintMargin(bool showPrintMargin) {
    _aceEditor.setShowPrintMargin(showPrintMargin);
  }

  /**
   * Sets a new theme for the editor. theme should exist, and be a directory
   * path, like ace/theme/textmate.
   */
  void setTheme(String theme) {
    _aceEditor.setTheme(theme);
  }

  void toggleCommentLines() {
    _aceEditor.toggleCommentLines();
  }

  List<String> getThemes() {
    String themes = i18n('ace_themes');

    return themes.split(',').map((String str) => "ace/theme/${str}");
  }

  List<String> getModes() {
    String modes = i18n('ace_modes');

    return modes.split(',').map((String str) => "ace/mode/${str}");
  }

  void dispose() {
    jsRelease(_aceEditor);
  }

  DivElement get aceContainer => _aceContainer;
}

class AceEditSession {
  StreamController<SessionChangeEvent> streamController =
      new StreamController<SessionChangeEvent>();

  var proxy;
  js.Callback changeListener;

  AceDocument document;
  AceUndoManager undoManager;
  AceSelection selection;

  // TODO: breakpoint code

  AceEditSession() {
    js.scoped(() {
      proxy = new js.Proxy(_ace.EditSession, "", "ace/mode/dart");
      js.retain(proxy);

      document = new AceDocument(proxy);
      undoManager = new AceUndoManager(proxy);
      selection = new AceSelection(proxy);

      changeListener = new js.Callback.many(_changeHandler);
      proxy.on("change", changeListener);
    });
  }

  AceDocument getDocument() {
    return document;
  }

  /**
   * Returns the current undo manager.
   */
  AceUndoManager getUndoManager() {
    return undoManager;
  }

  /**
   * TODO: this method may not exist - we may need to destroy the session and
   * start another to change modes
   */
  void setMode(String mode) {
    proxy.setMode(mode);
  }

  /**
   * Returns the current tab size.
   */
  num getTabSize() {
    return proxy.getTabSize();
  }

  /**
   * Returns the current value for tabs. If the user is using soft tabs, this
   * will be a series of spaces (defined by getTabSize()); otherwise it's simply
   * '\t'.
   */
  String getTabString() {
    return proxy.getTabString();
  }

  /**
   * Returns true if soft tabs are being used, false otherwise.
   */
  bool getUseSoftTabs() {
    return proxy.getUseSoftTabs();
  }

  /**
   * Set the number of spaces that define a soft tab; for example, passing in 4
   * transforms the soft tabs to be equivalent to four spaces. This function
   * also emits the changeTabSize event.
   */
  void setTabSize(int tabSize) {
    proxy.setTabSize(tabSize);
  }

  /**
   * Pass true to enable the use of soft tabs. Soft tabs means you're using
   * spaces instead of the tab character ('\t').
   */
  void setUseSoftTabs(bool useSoftTabs) {
    proxy.setUseSoftTabs(useSoftTabs);
  }

  AceSelection getSelection() {
    return selection;
  }

  void dispose() {
    jsRelease(proxy);

    document.dispose();
    undoManager.dispose();
    selection.dispose();

    changeListener.dispose();
    streamController.close();
  }

  void _changeHandler(var event, var foo) {
    streamController.add(new SessionChangeEvent());
  }

  Stream<SessionChangeEvent> get onChange => streamController.stream;
}

class AceSelection {
  var proxy;

  AceSelection(var sessionProxy) {
    proxy = sessionProxy.getSelection();
    js.retain(proxy);
  }

  void clearSelection() {
    proxy.clearSelection();
  }

  void selectAll() {
    proxy.selectAll();
  }

  /*
   * Sets the selection to the provided range.
   */
  void setSelectionRange(Point start, Point end, [bool reverse = false]) {
    proxy.setSelectionRange(_createRange(start, end), reverse);
  }

  dynamic _createRange(Point start, Point end) {
    //new Range(Number startRow, Number startColumn, Number endRow, Number endColumn)
    //return new js.Proxy(_ace.Range, start.y, start.x, end.y, end.x);

    // Range is hard to construct - it is a native type on many browsers.
    var range = proxy.getRange();
    range.setStart(start.y, start.x);
    range.setEnd(end.y, end.x);
    return range;
  }

  void dispose() {
    jsRelease(proxy);
  }
}

class AceDocument {
  var documentProxy;

  AceDocument(var sessionProxy) {
    documentProxy = sessionProxy.getDocument();
    js.retain(documentProxy);
  }

  String getValue() {
    return documentProxy.getValue();
  }

  void setValue(String contents) {
    documentProxy.setValue(contents);
  }

  /**
   * Converts an index position in a document to a {row, column} object.
   */
  Point indexToPosition(int index) {
    var obj = documentProxy.indexToPosition(index, 0);

    return new Point(obj.column, obj.row);
  }

  void dispose() {
    jsRelease(documentProxy);
  }
}

class AceUndoManager {
  var proxy;

  AceUndoManager(var sessionProxy) {
    proxy = sessionProxy.getUndoManager();
    js.retain(proxy);
  }

  /**
   * Returns true if there are redo operations left to perform.
   */
  bool hasRedo() {
    return proxy.hasRedo();
  }

  /**
   * Returns true if there are undo operations left to perform.
   */
  bool hasUndo() {
    return proxy.hasUndo();
  }

  /**
   * Destroys the stack of undo and redo redo operations.
   */
  void reset() {
    proxy.reset();
  }

  /**
   * Perform a redo operation on the document, reimplementing the last change.
   */
  void redo(bool dontSelect) {
    proxy.redo(dontSelect);
  }

  /**
   * Perform an undo operation on the document, reverting the last change.
   */
  void undo(bool dontSelect) {
    proxy.undo(dontSelect);
  }

  void dispose() {
    jsRelease(proxy);
  }
}

class SessionChangeEvent {

}
