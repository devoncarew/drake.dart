// UI workbench code.

library workbench;

import 'dart:async';
import 'dart:html';

import '../packages/chrome/app.dart' as chrome;

import 'ace.dart';
import 'analysis.dart';
import 'bootstrap.dart';
import 'filesystem_sdk.dart';
import 'jobs.dart';
import 'preferences.dart';
import 'preferences_chrome.dart';
import 'widgets.dart';
import 'workspace.dart' as ws;

// a workbench has:
// - a singleton
// - several layout areas
// - several editors
// - a title / menu area
// - status / progress area
// each layout are has zero or more views

/**
 * The [Workbench] singleton;
 */
Workbench workbench;

class Workbench {
  StreamController<WorkbenchEvent> eventStream =
      new StreamController<WorkbenchEvent>();
  Stream<WorkbenchEvent> _stream;

  TitleArea titleArea;
  StatusLine statusLine;

  Element leftNav;
  MessageArea messageArea;
  Element bottomNav;

  _EditorManager _editorManager;

  ws.Workspace _workspace;

  FilesView _filesView;
  OutlineView _outlineView;
  ConsoleView _consoleView;
  ProblemsView _problemsView;
  AceEditor _aceEditor;

  ViewPartContainer navigatorContainer;
  ViewPartContainer outlineContainer;
  ViewPartContainer outputContainer;

  Map<String, Action> actionMap = new Map<String, Action>();

  JobManager jobManager = new JobManager();

  ContentManager contentManager = new ContentManager();

  Workbench.instantiate(BodyElement body) {
    workbench = this;

    _stream = eventStream.stream.asBroadcastStream();

    _initializeWorkspace();

    titleArea = new TitleArea(body);

    navigatorContainer = new ViewPartContainer(this, query('#leftNav'));
    messageArea = new MessageArea(body);
    _editorManager = new _EditorManager(this, query('#editorArea'));
    outlineContainer = new ViewPartContainer(this, query('#rightNav'));
    outputContainer = new ViewPartContainer(this, query('#bottomNav'));
    FlexLayout.child.minHeight(query('#bottomNav'), "10em");

    statusLine = new StatusLine(body);
    _initJobsListener();

    _initDefaultContentTypes();

    _filesView = navigatorContainer.add(new FilesView(workbench));
    _outlineView = outlineContainer.add(new OutlineView(workbench));
    _problemsView = outputContainer.add(new ProblemsView(workbench));
    _consoleView = outputContainer.add(new ConsoleView(workbench));

    _aceEditor = new AceEditor(_editorManager.tabContainer);

    document.onKeyDown.listen(_handleKeyEvent);
  }

  void setBrand(String brand) {
    query("#brand").text = brand;
  }

  void addEditor(EditorPart editor) {
    _editorManager.addEditor(editor);
  }

  void setActiveEditor(EditorPart editor) {
    _editorManager.setActive(editor);
  }

  EditorPart getActiveEditor() {
    return _editorManager.activeEditor;
  }

  List<EditorPart> getEditors() {
    return _editorManager.editors;
  }

  ConsoleView get console => _consoleView;
  OutlineView get outline => _outlineView;
  FilesView get files => _filesView;

  void selectNextTab() {
    _editorManager.selectNextTab();
  }

  void selectPreviousTab() {
    _editorManager.selectPreviousTab();
  }

  void registerAction(Action action) {
    actionMap[action.id] = action;
  }

  Action getAction(String id) {
    return actionMap[id];
  }

  Iterable<Action> getActions() {
    return actionMap.values;
  }

  void fireWorkbenchEvent() {
    eventStream.add(new WorkbenchEvent());
  }

  Stream<WorkbenchEvent> get onChange => _stream;

  AceEditor get aceEditor => _aceEditor;

  /**
   * The workspace to use with this [Workbench];
   */
  ws.Workspace get workspace => _workspace;

  /**
   * A preference store for the application. This should be used for high-bandwidth
   * preferences, and non-user preferences settings.
   */
  PreferenceStore get prefs => chromePrefsLocal;

  /**
   * A low-bandwidth preference store. This should be used for user settings
   * that need to persist across various user machines. Care should be used
   * about how frewuently this is written to; there are strict quotas in terms
   * of size and writes per hour.
   */
  PreferenceStore get prefsSync => chromePrefsSync;

  void _handleKeyEvent(KeyEvent event) {
    if (!event.altKey && !event.ctrlKey && !event.metaKey) {
      return;
    }

    for (Action action in getActions()) {
      if (action.matches(event)) {
        event.preventDefault();

        if (action.enabled) {
          action.invoke();
        }
      }
    }
  }

  void _initializeWorkspace() {
    //registerChromeFileSystem();
    registerSdkFileSystem();

    _workspace = new ws.Workspace(prefs);
    // make sure that the sdk filesystem is linked in
    _workspace.initialize().then((ws.Workspace workspace) {
      if (workspace.getChildren().isEmpty) {
        // TODO: we should check for it already existing
        _workspace.link(sdkFileSystem.root);
      }
    });
  }

  void _initJobsListener() {
    jobManager.onChange.listen((JobManagerEvent e) {
      if (e.started) {
        statusLine.setStatus(e.job.name + "...");
        statusLine.progress.setIndeterminate(false);
        statusLine.progress.value = 0;
        statusLine.statusText.visibility(true);
        statusLine.progress.visibility(true);
      } else if (e.finished) {
        statusLine.clearStatus();
        statusLine.statusText.visibility(false);
        statusLine.progress.visibility(false);
      } else {
        if (e.indeterminate) {
          statusLine.progress.setIndeterminate(true);
        } else {
          statusLine.progress.value = (e.progress * 100).toInt();
        }
      }
    });
  }

  void _initDefaultContentTypes() {
    contentManager.register(new DefaultContentHandler('css'));
    contentManager.register(new DefaultContentHandler('dart'));
    contentManager.register(new DefaultContentHandler('html'));
    contentManager.register(new DefaultContentHandler('javascript'));
    contentManager.register(new DefaultContentHandler('json'));
    contentManager.register(new DefaultContentHandler('less'));
    contentManager.register(new DefaultContentHandler.ext('markdown', ['md']));
    contentManager.register(new DefaultContentHandler.ext('text', ['txt', 'text']));
    contentManager.register(new DefaultContentHandler('xml'));
    contentManager.register(new DefaultContentHandler('yaml'));
  }
}

class WorkbenchAction extends Action {
  Workbench workbench;

  WorkbenchAction(this.workbench, String id, String name) : super(id, name) {
    workbench.onChange.listen((WorkbenchEvent event) {
      updateEnabled();
    });

    updateEnabled();
  }

  void updateEnabled() {

  }
}

// TODO: we need to include info about the type of event
/**
 * Fired when there's a change in state of the workbench. For example, when the
 * active editor changes.
 */
class WorkbenchEvent {

}

/**
 * TODO: also listen for changes to the current editor part
 */
class EditorAction extends WorkbenchAction {

  EditorAction(Workbench workbench, String id, String name) :
    super(workbench, id, name);

  void invoke() {
    EditorPart editor = workbench.getActiveEditor();

    if (editor != null) {
      invokeEditor(editor);
    }
  }

  void invokeEditor(EditorPart editor) {

  }

  void updateEnabled() {
    enabled = (workbench.getActiveEditor() != null);
  }
}

class _EditorManager extends BTabContainerListener {
  Workbench workbench;
  BTabContainer tabContainer;
  Expando<BTab> editorTabExpando = new Expando<BTab>();

  List<EditorPart> editors = new List<EditorPart>();
  EditorPart _activeEditor;

  _EditorManager(this.workbench, Element editorArea) {
    tabContainer = new BTabContainer(query('#editorArea'));
    tabContainer.listeners.add(this);
  }

  void addEditor(EditorPart editor) {
    editors.add(editor);
    editor.contentDiv = editor.createContent(tabContainer.content);

    editorTabExpando[editor] = tabContainer.createTab();
    _updateEditorState(editor);

    editor.onEvent.listen((var event) {
      _updateEditorState(editor);
    });

    setActive(editor);
  }

  void setActive(EditorPart editor) {
    if (_activeEditor != editor) {
      _deactivate(_activeEditor);
      _activeEditor = editor;
      _activate(_activeEditor);

      workbench.fireWorkbenchEvent();
    }
  }

  bool isActive(EditorPart editor) {
    return editor == _activeEditor;
  }

  void closeEditor(EditorPart editor) {
    BTab tab = editorTabExpando[editor];

    selectRighthandTab();

    editors.remove(editor);
    tabContainer.removeTab(tab);
    editor.dispose();

    if (_activeEditor == editor) {
      setActive(null);
    }
  }

  void _activate(EditorPart part) {
    if (part != null) {
      tabContainer.setActive(editorTabExpando[part]);
      part.handleActivated();
    }
  }

  void _deactivate(EditorPart part) {
    if (part != null) {
      part.handleDeactivated();
    }
  }

  EditorPart get activeEditor => _activeEditor;

  void selectNextTab() {
    if (editors.length > 1) {
      int index = editors.indexOf(_activeEditor) + 1;
      if (index >= editors.length) {
        index = 0;
      }
      setActive(editors[index]);
    }
  }

  void selectPreviousTab() {
    if (editors.length > 1) {
      int index = editors.indexOf(_activeEditor) - 1;
      if (index < 0) {
        index = editors.length - 1;
      }
      setActive(editors[index]);
    }
  }

  /**
   * Select the tab to the right; if there is none, select the one to the left.
   */
  void selectRighthandTab() {
    if (editors.length > 1) {
      int index = editors.indexOf(_activeEditor) + 1;
      if (index >= editors.length) {
        index -= 2;
      }
      setActive(editors[index]);
    }
  }

  void focusRequest(BTab tab) {
    setActive(_getEditorForTab(tab));
  }

  void closeRequest(BTab tab) {
    _getEditorForTab(tab).close();
  }

  EditorPart _getEditorForTab(BTab tab) {
    for (EditorPart part in editors) {
      if (editorTabExpando[part] == tab) {
        return part;
      }
    }

    return null;
  }

  void _updateEditorState(EditorPart editor) {
    editorTabExpando[editor].setName(editor.name);

    if (editor is TextEditorPart) {
      TextEditorPart textEditorPart = editor as TextEditorPart;

      editorTabExpando[editor].setDirty(textEditorPart.dirty);
    }
  }
}

abstract class WorkbenchPart {
  StreamController<WorkbenchPartEvent> eventStream =
      new StreamController<WorkbenchPartEvent>();
  Workbench workbench;

  Stream<WorkbenchPartEvent> _stream;

  String _name;
  Element contentDiv;

  WorkbenchPart(this.workbench, [String inName]) {
    _stream = eventStream.stream.asBroadcastStream();
    _name = inName;
  }

  Element createContent(Element container);

  void handleActivated() {
    contentDiv.style.display = '-webkit-flex';
    contentDiv.focus();
  }

  void handleDeactivated() {
    contentDiv.style.display = 'none';
  }

  void dispose() {
    eventStream.close();

    if (contentDiv != null && contentDiv.parent != null) {
      contentDiv.parent.children.remove(contentDiv);
    }
  }

  void firePartEvent() {
    eventStream.add(new WorkbenchPartEvent());
  }

  String get name => _name;

  set name(String value) {
    if (_name != value) {
      _name = value;
      firePartEvent();
    }
  }

  Stream<WorkbenchPartEvent> get onEvent => _stream;
}

/**
 * Holds zero or more view parts.
 */
class ViewPartContainer {
  Workbench workbench;
  Element header;
  Element content;

  ViewPart _activePart;
  Map<ViewPart, BListItem> partMap = new Map<ViewPart, BListItem>();

  ViewPartContainer(this.workbench, Element parent) {
    header = new BUnorderedList(parent).navPills().nav().element;
    content = new BDiv(parent).well().clazz('viewContent').element;

    FlexLayout.container.vertical(content);
    FlexLayout.child.grab(content, 20);
  }

  ViewPart add(ViewPart part) {
    part.viewPartContainer = this;

    BListItem listItem = new BListItem(header);
    listItem.add(new BElement.a().text(part.name));
    partMap[part] = listItem;

    if (_activePart == null) {
      activate(part);
    }

    listItem.element.onClick.listen((_) {
      activate(part);
    });

    return part;
  }

  void activate(ViewPart part) {
    if (_activePart != part) {
      _deactivate(_activePart);
      _activate(part);
    }
  }

  void _activate(ViewPart part) {
    if (part != null) {
      _activePart = part;

      if (part.contentDiv == null) {
        part.contentDiv = part.createContent(content);
      }

      part.handleActivated();
      partMap[part].toggleActive();
    }
  }

  void _deactivate(ViewPart part) {
    if (part != null) {
      partMap[part].toggleActive();
      part.handleDeactivated();
      _activePart = null;
    }
  }

  ViewPart get activePart => _activePart;
}

class ViewPart extends WorkbenchPart {
  ViewPartContainer viewPartContainer;

  ViewPart(Workbench workbench, String partName) : super(workbench, partName);

  Element createContent(Element container) {
    BDiv div = new BDiv(container);
    createViewContent(div.element);
    FlexLayout.container.vertical(div.element);
    FlexLayout.child.grab(div.element, 20);
    return div.element;
  }

  void createViewContent(Element content) {

  }
}

abstract class EditorPart extends WorkbenchPart {
  bool _dirty;
  Timer _reconcileTimer;

  EditorPart(Workbench workbench) : super(workbench);

  Future<EditorPart> save() {
    return new Future.value(this);
  }

  Future<EditorPart> saveAs() {
    return new Future.value(this);
  }

  bool get dirty => _dirty;

  set dirty(bool value) {
    if (_dirty != value) {
      _dirty = value;
      firePartEvent();
    }

    _startReconcileTimer();
  }

  void fireReconcileEvent() {
    eventStream.add(new EditorReconcileEvent());
  }

  void close() {
    if (dirty) {
      YesNoDialog dialog = new YesNoDialog(
          "Close File", "Save file changes?",
          ["Save Changes", "Discard Changes", "Cancel"]);

      workbench.messageArea.add(dialog);

      dialog.getResponse().then((int response) {
        if (response == 0) {
          save().then((_) {
            workbench._editorManager.closeEditor(this);
          });
        } else if (response == 1) {
          workbench._editorManager.closeEditor(this);
        }
      });
    } else {
      workbench._editorManager.closeEditor(this);
    }
  }

  void dispose() {
    if (_reconcileTimer != null) {
      _reconcileTimer.cancel();
      _reconcileTimer = null;
    }

    super.dispose();
  }

  void _startReconcileTimer() {
    if (_reconcileTimer != null) {
      _reconcileTimer.cancel();
    }

    _reconcileTimer = new Timer(
        new Duration(milliseconds: 500), fireReconcileEvent);
  }

}

class WorkbenchPartEvent {

}

class EditorReconcileEvent extends WorkbenchPartEvent {

}

abstract class TextEditorPart extends EditorPart {

  TextEditorPart(Workbench workbench) : super(workbench);

  Object get file;
  String get contents;

  void gotoLine(int line);

  void select(int offset, int length);

  ContentHandler getContentHandler() {
    return workbench.contentManager.getHandlerForName(name);
  }
}

class TitleArea {
  Element _header;
  Toolbar _toolbar;
  BMenubar _menubar;

  TitleArea(Element parent) {
    _header = query('header');
    _toolbar = new Toolbar();

    _menubar = new BMenubar();
    _toolbar.add(_menubar.element);
  }

  Toolbar get toolbar => _toolbar;

  BMenubar get menubar => _menubar;

  Element get brandElement => query('a.brand');

}

class MessageArea {
  Element _messageElement;

  MessageArea(Element parent) {
    _messageElement = query('#messageArea');
  }

  void showWarningAlert(String title, String message) {
    new BAlert(_messageElement).createTitleMessage().
      title(title).message(message).warning().closeButton();
  }

  void showErrorAlert(String title, String message) {
    new BAlert(_messageElement).createTitleMessage().
      title(title).message(message).error().closeButton();
  }

  void showInfoAlert(String title, String message) {
    new BAlert(_messageElement).createTitleMessage().
      title(title).message(message).info().closeButton();
  }

  void showSuccessAlert(String title, String message) {
    new BAlert(_messageElement).createTitleMessage().
      title(title).message(message).success().closeButton();
  }

  void add(BElement element) {
    _messageElement.children.add(element.element);
  }

  void clearAlerts() {
    _messageElement.children.clear();
  }
}

class StatusLine {
  Element _statusLine;
  BElement statusText;
  BProgress progress;

  StatusLine(Element parent) {
    _statusLine = query('#statusLine');

    BUnorderedList ul = new BUnorderedList(_statusLine).nav().pullRight();
    ul.element.style.marginTop = '0.5em';

    // separator
    //ul.add(new BListItem().dividerVertical());

    // status text
    BListItem li = ul.add(new BListItem());
    statusText = li.add(new BElement.p()/*.navbarText()*/);
    clearStatus();

    // separator
    li = ul.add(new BListItem());
    li.add(new BElement.p().innerHtml('&nbsp;&nbsp;'));

    // progress bar
    li = ul.add(new BListItem());
    progress = li.add(new BProgress().width('15em'));
    progress.value = 30;

    statusText.visibility(false);
    progress.visibility(false);
  }

  void setStatus(String status) {
    statusText.text(status);
  }

  void clearStatus() {
    statusText.innerHtml('&nbsp;');
  }

//  void addSeparator() {
//    BElement ul = new BUnorderedList(_statusLine).nav();
//    ul.add(new BListItem().dividerVertical());
//  }

  void toggleNavbarInverse() {
    Element parent = _statusLine.parent.parent;
    parent.classes.toggle('navbar-inverse');
  }
}

class FilesView extends ViewPart {
  TreeViewer treeViewer;

  FilesView(Workbench workbench) : super(workbench, 'Files');


  void createViewContent(Element container) {
    treeViewer = new TreeViewer(container);
    treeViewer.labelProvider = new ResourceLabelProvider();

    treeViewer.addHeader("Loose Files");
    treeViewer.addContentProvider(new FilesContentProvider());
    treeViewer.addHeader("Folders");
    treeViewer.addContentProvider(new FoldersContentProvider());
    treeViewer.addDivider();
    treeViewer.addHeader("Dart SDK");
    treeViewer.addContentProvider(new FoldersContentProvider(true));

    FlexLayout.child.grab(treeViewer.element, 20);
  }

  void setWorkspace(ws.Workspace workspace) {
    treeViewer.setInput(workspace);
  }

/*  void createViewContent(Element container) {
    container.innerHtml = """
<ul class="nav nav-list" style="-webkit-flex: 20 1 0px;">
  <li class="nav-header">Loose Files</li>
  <li class="active"><a>foo.dart</a></li>
  <li><a>bar.dart</a></li>
  <li><a>baz.dart</a></li>

  <li class="nav-header">Folders</li>
  <li><a>one/</a></li>
  <li><a>two/</a></li>
  <li><a>three/</a></li>

  <li class="divider"></li>

  <li class="nav-header">Dart SDK</li>
  <li><a>dart:chrome</a></li>
  <li><a>dart:core</a></li>
  <li><a>dart:html</a></li>
</ul>
""";
  }*/
}


class OutlineView extends ViewPart {
  TreeViewer treeViewer;
  TextEditorPart focusedEditor;
  StreamSubscription editorSubscription;

  OutlineView(Workbench workbench) : super(workbench, 'Outline');

  void createViewContent(Element container) {
    treeViewer = new TreeViewer(container);
    treeViewer.labelProvider = new AstLabelProvider();
    treeViewer.addContentProvider(new AstContentProvider());
    treeViewer.onSelectionChange.listen(_handleSelectionChanged);

    FlexLayout.child.grab(treeViewer.element, 20);

    workbench.onChange.listen(_activeEditorChange);
  }

  // TODO: this is short-circuiting a bunch of architecture
  // (i.e. a PageBookViewPart, tracking the active editor, a reconciler, ...)
  void setInput(var input) {
    treeViewer.setInput(input);
  }

  void _activeEditorChange(WorkbenchEvent event) {
    TextEditorPart editor = getCurrentEditor();

    if (editor == focusedEditor) {
      return;
    }

    if (focusedEditor != null) {
      editorSubscription.cancel();;
      editorSubscription = null;
    }

    focusedEditor = editor;

    if (focusedEditor != null) {
      editorSubscription = focusedEditor.onEvent
          .where((e) => e is EditorReconcileEvent)
          .listen((e) {
        _doParse();
      });
    }

    _doParse();
  }

  void _doParse() {
    if (focusedEditor != null && focusedEditor.getContentHandler().isDartMode) {
      analysisParseString(focusedEditor.contents, focusedEditor.file).then((AnalysisResult result) {
        workbench.outline.setInput(result.ast);
      });
    } else {
      setInput(null);
    }
  }

  void dispose() {
    if (editorSubscription != null) {
      editorSubscription.cancel();
      editorSubscription = null;
    }

    super.dispose();
  }

  TextEditorPart getCurrentEditor() {
    EditorPart editor = workbench.getActiveEditor();

    if (editor is TextEditorPart) {
      return editor as TextEditorPart;
    } else {
      return null;
    }
  }

  void _handleSelectionChanged(SelectionEvent event) {
    ASTNode node = _getMoreSpecificNode(event.selection.single);
    EditorPart part = this.workbench.getActiveEditor();

    if (part is TextEditorPart) {
      TextEditorPart editor = part as TextEditorPart;

      editor.select(node.offset, node.length);

      if (event.doubleClick) {
        this.workbench.setActiveEditor(editor);
      }
    }
  }

  ASTNode _getMoreSpecificNode(ASTNode node) {
    if (node is ClassDeclaration) {
      return (node as ClassDeclaration).name;
    } else if (node is FunctionDeclaration) {
      return (node as FunctionDeclaration).name;
//    } else if (node is FieldDeclaration) {
//      return (node as FieldDeclaration).name;
    } else if (node is ConstructorDeclaration) {
      ConstructorDeclaration ctor = node as ConstructorDeclaration;

      if (ctor.name == null) {
        return ctor.returnType;
      } else {
        return ctor.name;
      }
    } else if (node is MethodDeclaration) {
      return (node as MethodDeclaration).name;
    } /*else if (node is TopLevelVariableDeclaration) {
      return (node as TopLevelVariableDeclaration).name;
    }*/

    return node;
  }
}

// TODO: implement and use for the outline view
class PageBookViewPart extends ViewPart {

  PageBookViewPart(Workbench workbench, String name) : super(workbench, name) {

  }

}

class ProblemsView extends ViewPart {

  ProblemsView(Workbench workbench) : super(workbench, 'Problems') {

  }

  void createViewContent(Element container) {
    BTable table = new BTable(container).tableHover().tableCondensed();
    table.clazz('problemsView');

    BElement row = table.createRow();
    BElement cell = table.createCell(row);
    cell.innerHtml('<span class="label label-important">error</span>');
    cell = table.createCell(row);
    cell.innerHtml('Foo bar baz <span class="muted">workbench.dart:1</span>');

    row = table.createRow();
    cell = table.createCell(row);
    cell.innerHtml('<span class="label label-warning">warning</span>');
    cell = table.createCell(row);
    cell.innerHtml('Foo bar baz <span class="muted">workbench.dart:4</span>');

    row = table.createRow();
    cell = table.createCell(row);
    cell.innerHtml('<span class="label label-warning">warning</span>');
    cell = table.createCell(row);
    cell.innerHtml('Lorem ipsum dolor sit amet, consectetur adipisicing elit <span class="muted">workbench.dart:12</span>');

    row = table.createRow();
    cell = table.createCell(row);
    cell.innerHtml('<span class="label label-warning">warning</span>');
    cell = table.createCell(row);
    cell.innerHtml('Foo bar baz <span class="muted">workbench.dart:4</span>');

    row = table.createRow();
    cell = table.createCell(row);
    cell.innerHtml('<span class="label label-info">todo</span>');
    cell = table.createCell(row);
    cell.innerHtml('Foo bar baz <span class="muted">workbench.dart:3</span>');

//    table.innerHtml("""
//<span class="label label-important">error</span> Foo bar baz <span class="muted">workbench.dart:1</span><br>
//<span class="label label-warning">warning</span> Foo bar baz <span class="muted">workbench.dart:2</span><br>
//<span class="label label-warning">warning</span> Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore<br>
//<span class="label label-warning">warning</span> Foo bar baz <span class="muted">workbench.dart:3</span><br>
//<span class="label label-warning">warning</span> Foo bar bar<br>
//<span class="label label-warning">warning</span> Foo bar baz<br>
//<span class="label label-info">todo</span> Foo bar baz<br>
//""");

    FlexLayout.child.grab(table.element, 20);
  }

}

class ConsoleView extends ViewPart {

  ConsoleView(Workbench workbench) : super(workbench, 'Output') {

  }

  void createViewContent(Element container) {
    container.classes.add('consoleOut');
  }

  void append(String text) {
    // TODO: we should have a way to indicate that there's a change;
    // we shouldn't just activate the view
    viewPartContainer.activate(this);

    contentDiv.text += "${text}\n";
  }
}

//class DebuggerView extends ViewPart {
//
//  DebuggerView(Element parent) : super(parent, 'Debugger') {
//
//  }
//
//}

class Toolbar {
  DivElement container;

  Toolbar() {
    container = query('#toolbar');
  }

  void add(Element element) {
    container.children.add(element);
  }

  void toggleNavbarInverse() {
    final inverse = 'navbar-inverse';
    final classes = container.parent.parent.classes;

    if (classes.contains(inverse)) {
      classes.remove(inverse);
    } else {
      classes.add(inverse);
    }
  }
}

/**
 * A TextEditorPart implementation tjat wraps the Ace editor.
 *
 * See: http://ajaxorg.github.io/ace/
 * API: http://ajaxorg.github.io/ace/#nav=api
 */
class AceEditorPart extends TextEditorPart {
  chrome.ChromeFileEntry _file;

  AceEditor aceEditor;
  AceEditSession session;

  AceEditorPart(Workbench workbench, [chrome.ChromeFileEntry file]) : super(workbench) {
    this._file = file;

    name = _file == null ? 'untitled' : _file.name;

    aceEditor = workbench.aceEditor;

    session = new AceEditSession();

    session.setMode(getContentHandler().aceMode);

    session.onChange.listen((var event) {
      dirty = true;
    });
  }

  Object get file => _file;

  String get contents {
    return session.getDocument().getValue();
  }

  void gotoLine(int line) {
    aceEditor.gotoLine(line, 0, false);
  }

  void select(int offset, int length) {
    Point start = session.getDocument().indexToPosition(offset);
    Point end = session.getDocument().indexToPosition(offset + length);

    session.getSelection().setSelectionRange(start, end);
  }

  Element createContent(Element container) {
    if (_file != null) {
      _file.readContents().then((String contents) {
        session.getDocument().setValue(contents);
        aceEditor.navigateFileStart();
        dirty = false;
        fireReconcileEvent();

        // TODO: we need the ability to turn on and off ignoring dirty changes
        Timer.run(() => dirty = false);
      });
    }

    return aceEditor.aceContainer;
  }

  void handleActivated() {
    aceEditor.setSession(session);
    aceEditor.show();
    aceEditor.resize();
    aceEditor.focus();
  }

  Future<EditorPart> save() {
    if (_file == null) {
      return saveAs();
    }

    Completer completer = new Completer();

    if (dirty) {
      // TODO: there is a race condition here if they type during long saves
      // we need to set the editor as read-only, and show a busy state
      _file.writeContents(contents).then((chrome.ChromeFileEntry f) {
        dirty = false;
        completer.complete(this);
      }).catchError((var error) {
        workbench.messageArea.showErrorAlert(
            'Error Saving ${name}', error.toString());
        completer.completeError(error);
      });
    }

    return completer.future;
  }

  Future<EditorPart> saveAs() {
    Completer completer = new Completer();

    chrome.fileSystem.chooseSaveFile().then((chrome.ChromeFileEntry file) {
      if (file != null) {
        _file = file;
        name = _file.name;

        ContentHandler handler =
            this.workbench.contentManager.getHandlerForName(name);
        session.setMode(handler.aceMode);

        save().then((var result) {
          completer.complete(result);
        }).catchError((var error) {
          completer.completeError(error);
        });
      } else {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  void handleDeactivated() {
    aceEditor.hide();
  }

  void dispose() {
    eventStream.close();

    if (_file != null) {
      _file.dispose();
    }

    session.dispose();
  }
}

class ResourceLabelProvider extends TreeLabelProvider {
  void render(TreeItem treeItem, ws.Resource resource) {
    treeItem.span.text = resource.name;
  }
}

class AstLabelProvider extends TreeLabelProvider {
  void render(TreeItem treeItem, ASTNode node) {
    String text;

    if (node is ClassDeclaration) {
      text = (node as ClassDeclaration).name.toString();
    } else if (node is FunctionDeclaration) {
      FunctionDeclaration dec = node as FunctionDeclaration;
      text = '${dec.name}()';
    } else if (node is TopLevelVariableDeclaration) {
      TopLevelVariableDeclaration variable = node as TopLevelVariableDeclaration;
      List<VariableDeclaration> vars = variable.variables.variables;
      if (vars.isEmpty) {
        text = '';
      } else if (vars.length == 1) {
        text = vars.first.name.toString();
      } else {
        text = '${vars.first.name.toString()}, ...';
      }
    } else if (node is LibraryDirective) {
      LibraryDirective directive = node as LibraryDirective;

      text = '${directive.keyword} ${directive.name}';
    } else if (node is PartOfDirective) {
      PartOfDirective directive = node as PartOfDirective;

      text = 'part of ${directive.libraryName}';
    } else if (node is UriBasedDirective) {
      UriBasedDirective directive = node as UriBasedDirective;

      text = '${directive.keyword} ${analysisLiteralToString(directive.uri)}';
    } else if (node is FieldDeclaration) {
      FieldDeclaration field = node as FieldDeclaration;

      List<VariableDeclaration> vars = field.fields.variables;
      if (vars.isEmpty) {
        text = '';
      } else if (vars.length == 1) {
        text = vars.first.name.toString();
      } else {
        text = '${vars.first.name.toString()}, ...';
      }
    } else if (node is ConstructorDeclaration) {
      ConstructorDeclaration ctor = node as ConstructorDeclaration;

      if (ctor.name == null) {
        text = '${ctor.returnType}()';
      } else {
        text = '${ctor.returnType}{ctor.name}()';
      }
    } else if (node is MethodDeclaration) {
      MethodDeclaration m = node as MethodDeclaration;

      text = '${m.name}()';
    } else if (node is FunctionTypeAlias) {
      FunctionTypeAlias f = node as FunctionTypeAlias;

      text = '${f.name}';
    } else {
      print(node.runtimeType.toString());
      text = node.toString();
    }

    treeItem.span.text = text;
  }
}

class FilesContentProvider extends ContentProvider {
  List emptyList = new List();

  List<ws.Resource> getRoots(ws.Workspace workspace) {
    return workspace.getChildren().where((ws.Resource r) {
      return r is ws.File;
    });
  }

  bool hasChildren(ws.Resource node) => false;

  List<ws.Resource> getChildren(ws.Resource node) {
    return emptyList;
  }

  Future<ws.Resource> getParent(ws.Resource node) {
    return new Future.value(null);
  }
}

class FoldersContentProvider extends ContentProvider {
  List emptyList = new List();
  bool readOnly;

  FoldersContentProvider([this.readOnly]);

  List<ws.Resource> getRoots(ws.Workspace workspace) {
    return workspace.getChildren().where((r) => r is ws.Folder);
  }

  // TODO:
  bool hasChildren(ws.Resource node) => true;

  List<ws.Resource> getChildren(ws.Resource node) {
    return emptyList;
  }

  Future<ws.Resource> getParent(ws.Resource node) {
    return new Future.value(null);
  }
}

class AstContentProvider extends ContentProvider {
  List emptyList = new List();

  AstContentProvider();

  List<ASTNode> getRoots(CompilationUnit unit) {
    List list = new List();

    list.addAll(unit.directives);
    list.addAll(unit.declarations);

    return list;
  }

  bool hasChildren(ASTNode node) {
    if (node is ClassDeclaration) {
      ClassDeclaration classDec = (node as ClassDeclaration);

      return !classDec.members.isEmpty;
    } else {
      return false;
    }
  }

  List<ASTNode> getChildren(ASTNode node) {
    if (node is ClassDeclaration) {
      ClassDeclaration classDec = (node as ClassDeclaration);

      return classDec.members;
    } else {
      return emptyList;
    }
  }

  Future<ASTNode> getParent(ASTNode node) {
    if (node.parent is ClassDeclaration) {
      return new Future.value(node.parent);
    } else {
      return new Future.value(null);
    }
  }
}

class ContentManager {
  Map<String, ContentHandler> _handlerMap = new Map();
  TextContentHandler textContentHandler = new TextContentHandler();

  register(ContentHandler handler) {
    for (String ext in handler.extensions) {
      _handlerMap[ext] = handler;
    }
  }

  ContentHandler getHandlerForName(String name) {
    int index = name.lastIndexOf('.');

    if (index == -1) {
      return getHandlerForExtension(name);
    } else {
      return getHandlerForExtension(name.substring(index + 1));
    }
  }

  ContentHandler getHandlerForExtension(String ext) {
    if (_handlerMap.containsKey(ext)) {
      return _handlerMap[ext.toLowerCase()];
    } else {
      return textContentHandler;
    }
  }
}

abstract class ContentHandler {
  String id;
  List<String> extensions = [];

  ContentHandler(this.id, this.extensions);

  String get aceMode => 'ace/mode/text';
  bool get isDartMode => id == 'dart';
}

class DefaultContentHandler extends ContentHandler {

  DefaultContentHandler(String ext) : super(ext, [ext]);

  DefaultContentHandler.ext(String type, List<String> extensions)
      : super(type, extensions);

  String get aceMode => 'ace/mode/${id}';
}

class TextContentHandler extends ContentHandler {
  TextContentHandler() : super('text', ['txt', 'text']);
}
