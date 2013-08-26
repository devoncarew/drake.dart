
library drake;

import 'dart:async';
import 'dart:html';

import 'packages/chrome/app.dart' as chrome;

import 'lib/analysis.dart';
import 'lib/bootstrap.dart';
import 'lib/debugger.dart';
import 'lib/debugger_vm.dart';
import 'lib/utils.dart';
import 'lib/jobs.dart';
import 'lib/widgets.dart';
import 'lib/workbench.dart';

import 'test/alltests.dart' as testing;

void main() {
  Drake drake = new Drake();
}

class Drake {
  Workbench workbench;

  BPopover aboutPopover;
  BPopover preferencesPopover;

  InputElement searchBox;

  DrakePreferences preferences = new DrakePreferences();

  Drake() {
    workbench = new Workbench.instantiate(query("body"));
    workbench.setBrand(i18n("app_name"));
    document.title = i18n("app_name");

    preferences.init();

    createAboutPopover(workbench.titleArea.brandElement);

    createActions();
    createMenubar();
    createToolbar();

    chrome.app.window.current.onClosed.listen(_handleWindowClosed);
  }

  void createActions() {
    // file
    workbench.registerAction(new FileNewAction(workbench));
    workbench.registerAction(new FileOpenAction(workbench));
    workbench.registerAction(new FileSaveAction(workbench));
    workbench.registerAction(new FileSaveAllAction(workbench));
    workbench.registerAction(new FileCloseAction(workbench));
    workbench.registerAction(new FileCloseAllAction(workbench));
    workbench.registerAction(new FileExitAction(workbench));

    // edit
    workbench.registerAction(new EditNextTabAction(workbench));
    workbench.registerAction(new EditPrevTabAction(workbench));
    workbench.registerAction(new EditGotoLineAction(workbench));

    // run
    // TODO: disabled until these features are better supported
//    workbench.registerAction(new RunRunAction(workbench));
//    workbench.registerAction(new RemoteDebugAction(workbench));

    // misc
    workbench.registerAction(new GlobalSearchAction(this, workbench));
  }

  void createMenubar() {
    BMenubar menubar = workbench.titleArea.menubar;

    // file menu
    BMenu fileMenu = new BMenu('File');
    fileMenu.add(createMenuItem(workbench.getAction('file-new')));
    fileMenu.add(createMenuItem(workbench.getAction('file-open')));
    fileMenu.addSeparator();
    fileMenu.add(createMenuItem(workbench.getAction('file-save')));
    fileMenu.add(createMenuItem(workbench.getAction('file-saveAll')));
    fileMenu.addSeparator();
    fileMenu.add(createMenuItem(workbench.getAction('file-close')));
    fileMenu.add(createMenuItem(workbench.getAction('file-closeAll')));
    fileMenu.addSeparator();
    fileMenu.add(createMenuItem(workbench.getAction('file-exit')));

    menubar.add(fileMenu);

    // edit menu
    BMenu editMenu = new BMenu('Edit');
    editMenu.add(new BMenuItem('Cut'));
    editMenu.add(new BMenuItem('Copy'));
    editMenu.add(new BMenuItem('Paste'));
    editMenu.addSeparator();
    editMenu.add(createMenuItem(workbench.getAction('edit-nextTab')));
    editMenu.add(createMenuItem(workbench.getAction('edit-prevTab')));
    editMenu.addSeparator();
    editMenu.add(createMenuItem(workbench.getAction('edit-gotoLine')));

    menubar.add(editMenu);

    // TODO: disabled until these features are better supported
//    // refactor menu
//    BMenu refactorMenu = new BMenu('Refactor');
//    refactorMenu.add(new BMenuItem('Rename'));
//
//    menubar.add(refactorMenu);
//
//    // run menu
//    BMenu runMenu = new BMenu('Run');
//    runMenu.add(createMenuItem(workbench.getAction('run-run')));
//    runMenu.add(createMenuItem(workbench.getAction('run-remoteDebug')));
//
//    menubar.add(runMenu);

    // tools menu
    BMenu toolsMenu = new BMenu('Tools');
    toolsMenu.add(new BMenuItem('Debug: job 1', handleJob1));
    toolsMenu.add(new BMenuItem('Debug: job 2', handleJob2));
    toolsMenu.addSeparator();
    toolsMenu.add(new BMenuItem('Debug: alert info', (_) {
      workbench.messageArea.showInfoAlert("Alert!", 'info level message');
    }));
    toolsMenu.add(new BMenuItem('Debug: alert success', (_) {
      workbench.messageArea.showSuccessAlert("Alert!", 'success level message');
    }));
    toolsMenu.add(new BMenuItem('Debug: alert warning', (_) {
      workbench.messageArea.showWarningAlert("Alert!", 'warning level message');
    }));
    toolsMenu.add(new BMenuItem('Debug: alert error', (_) {
      workbench.messageArea.showErrorAlert("Alert!", 'error level message');
    }));
    toolsMenu.addSeparator();
    toolsMenu.add(new BMenuItem('Debug: Analyze', handleAnalyze));
    toolsMenu.addSeparator();
    toolsMenu.add(new BMenuItem('Run Tests', handleRunTests));

    menubar.add(toolsMenu);
  }

  void createToolbar() {
    Toolbar toolbar = workbench.titleArea.toolbar;

    BUnorderedList ul = new BUnorderedList().nav().pullRight();
    toolbar.add(ul.element);

    // search element
    BListItem li = ul.add(new BListItem());
    BElement input = li.add(new BInputElement().searchQuery().navbarSearch().
        type('text').placeholder('Search'));
    searchBox = input.element;
    searchBox.onChange.listen((var event) {
      // TODO: handle search action
      workbench.messageArea.showWarningAlert("TODO: search", searchBox.value);
    });

    // vertical separator
    ul.add(new BListItem().dividerVertical());

    // wrench button
    li = ul.add(new BListItem());
    BButton wrenchButton = li.add(new BButton().buttonMini());
    wrenchButton.add(new BImage().src('images/icons/tools.png'));
    createPreferencesPopover(wrenchButton.element);
  }

  void createAboutPopover(Element relativeTo) {
    String appName = i18n("app_name");
    String appDescription = i18n("app_description");
    String version = chrome.runtime.getManifest()['version'];

    aboutPopover = new BPopover(relativeTo);
    aboutPopover.setTitle("About");
    aboutPopover.contentElement.innerHtml = """
<div class="media">
  <a class="pull-left">
    <img class="media-object" src="images/drake.png" width="64" height="64">
  </a>
  <div class="media-body">
    <h4 class="media-heading">${appName}</h4>
    <p>${appDescription}<br>version ${version}</p>
  </div>
  <hr>
  <p class="text-center">Application is up to date.</p>
</div>
""";

    // TODO: check for updates, add icons, and a link to dartlang.org

    relativeTo.onClick.listen((_) {
      aboutPopover.toggleVisibility();
    });
  }

  void createPreferencesPopover(Element relativeTo) {
    preferencesPopover = new BPopover(relativeTo, dockLeft: false);
    preferencesPopover.setTitle("Settings");
    preferencesPopover.width = "30em";

    BForm form = null;

    relativeTo.onClick.listen((_) {
      if (form == null) {
        form = new BForm(preferencesPopover.contentElement);
        BFieldset fieldSet = new BFieldset();
        fieldSet.add(new BElement.legend().innerHtml('Editing'));
        form.add(fieldSet);

        BElement label;
        BInputElement checkbox;

        label = new BElement.label().clazz('checkbox').text("Show print margin");
        checkbox = label.add(new BInputElement().checkbox());
        checkbox.checked = preferences.showPrintMargin;
        checkbox.element.onChange.listen((_) {
          // TODO: use a binding for this
          preferences.showPrintMargin = checkbox.checked;
        });
        fieldSet.add(label);

        fieldSet = new BFieldset();
        fieldSet.add(new BElement.legend().innerHtml('Themes'));
        form.add(fieldSet);

        label = new BElement.label().clazz('checkbox').text("Application: ");
        BSelect bootstrapSelect = label.add(new BSelect());
        for (String str in bootstrapManager.getThemes()) {
          bootstrapSelect.createOption(str, str == preferences.bootstrapTheme);
        }
        bootstrapSelect.element.onChange.listen((_) {
          preferences.bootstrapTheme = bootstrapSelect.getSelectedItem();
        });
        fieldSet.add(label);

        label = new BElement.label().clazz('checkbox').text("Editor: ");
        BSelect aceSelect = label.add(new BSelect());
        for (String str in workbench.aceEditor.getThemes()) {
          aceSelect.createOption(str, str == preferences.aceTheme);
        }
        aceSelect.element.onChange.listen((_) {
          preferences.aceTheme = aceSelect.getSelectedItem();
        });
        fieldSet.add(label);
      }

      preferencesPopover.toggleVisibility();
    });
  }

  void handleAnalyze(var event) {
    EditorPart editor = workbench.getActiveEditor();

    if (editor is TextEditorPart) {
      TextEditorPart part = editor as TextEditorPart;

      analysisParseString(part.contents, part.file).then((AnalysisResult result) {
        // TODO: pretty print the errors
        for (AnalysisError error in result.errors) {
          workbench.console.append(error.toString());
        }
      });
    }
  }

  void handleRunTests(var event) {
    testing.runTests(workbench);
  }

  void handleJob1(var event) {
    workbench.jobManager.schedule(new TestJob(false));
  }

  void handleJob2(var event) {
    workbench.jobManager.schedule(new TestJob(true));
  }

  BMenuItem createMenuItem(Action action) {
    BMenuItem menuItem = new BMenuItem(action.name, (var event) {
      if (action.enabled) {
        action.invoke();
      }
    });

    if (action.binding != null) {
      menuItem.setAcceleratorDescription(action.binding.getDescription());
    }

    menuItem.setEnabled(action.enabled);

    action.onChange.listen((var event) {
      menuItem.setEnabled(action.enabled);
    });

    return menuItem;
  }

  void _handleWindowClosed(data) {
    // TODO:
    //print('_handleWindowClosed');
  }
}

class DrakePreferences {
  final PRINT_MARGIN = 'printMargin';
  final ACE_THEME = 'aceTheme';
  final BOOTSTRAP_THEME = 'boostrapTheme';

  bool _printMargin = null;
  String _aceTheme;
  String _bootstrapTheme;

  void init() {
    workbench.prefsSync.getValue(PRINT_MARGIN).then((String str) {
      showPrintMargin = (str == null ? true : "true" == str);
    });

    workbench.prefsSync.getValue(ACE_THEME).then((String str) {
      aceTheme = (str == null ? workbench.aceEditor.getTheme() : str);
    });

    workbench.prefsSync.getValue(BOOTSTRAP_THEME).then((String str) {
      bootstrapTheme = (str == null ? bootstrapManager.getTheme() : str);
    });
  }

  bool get showPrintMargin => _printMargin;

  set showPrintMargin(bool value) {
    if (_printMargin != value) {
      _printMargin = value;
      workbench.prefsSync.setValue(PRINT_MARGIN, value.toString());
    }

    if (workbench.aceEditor.getShowPrintMargin() != value) {
      workbench.aceEditor.setShowPrintMargin(value);
    }
  }

  String get aceTheme => _aceTheme;

  set aceTheme(String theme) {
    if (_aceTheme != theme) {
      _aceTheme = theme;
      workbench.prefsSync.setValue(ACE_THEME, theme);
    }

    if (workbench.aceEditor.getTheme() != theme) {
      workbench.aceEditor.setTheme(theme);
    }
  }

  String get bootstrapTheme => _bootstrapTheme;

  set bootstrapTheme(String theme) {
    if (_bootstrapTheme != theme) {
      _bootstrapTheme = theme;
      workbench.prefsSync.setValue(BOOTSTRAP_THEME, theme);
    }

    if (bootstrapManager.getTheme() != theme) {
      bootstrapManager.setTheme(theme);
    }
  }
}

class FileNewAction extends WorkbenchAction {
  FileNewAction(Workbench workbench) : super(workbench, "file-new", "New") {
    defaultBinding("ctrl-n");
  }

  void invoke() {
    workbench.addEditor(new AceEditorPart(workbench));
  }
}

class FileOpenAction extends WorkbenchAction {
  FileOpenAction(Workbench workbench) : super(workbench, "file-open", "Open...") {
    defaultBinding("ctrl-o");
  }

  void invoke() {
    chrome.fileSystem.chooseOpenFile().then((chrome.ChromeFileEntry file) {
      if (file != null) {
        // TODO: if the file is already open, active the editor

        workbench.addEditor(new AceEditorPart(workbench, file));

//        print("entry id = ${chrome.fileSystem.getEntryId(file)}");
//        print("file id = ${file.id}");
//        print("file name = ${file.name}");
//        print("file fullPath = ${file.fullPath}");
//        print("file toURL = ${file.toURL()}");
//        chrome.fileSystem.getDisplayPath(file).then((String str) {
//          print("display path = ${str}");
//        });

//        file.getParent().then((chrome.ChromeFileEntry parent) {
//          print("parent id = ${parent.id}");
//          print("parent name = ${parent.name}");
//          print("parent fullPath = ${parent.fullPath}");
//          print("parent toURL = ${parent.toURL()}");
//          chrome.fileSystem.getDisplayPath(parent).then((String str) {
//            print("parent display path = ${str}");
//          });
//        });
      }
    });
  }
}

class FileSaveAction extends EditorAction {
  FileSaveAction(Workbench workbench) : super(workbench, "file-save", "Save") {
    defaultBinding("ctrl-s");
  }

  // TODO: listen for editor dirty changes
//  void updateEnabled() {
//
//  }

  void invokeEditor(EditorPart editor) {
    editor.save();
  }
}

// TODO: listen for editor dirty changes
class FileSaveAllAction extends EditorAction {
  FileSaveAllAction(Workbench workbench) : super(workbench, "file-saveAll", "Save All") {
    defaultBinding("ctrl-shift-s");
  }

  void updateEnabled() {
    enabled = workbench.getEditors().any((EditorPart part) {
      return part.dirty;
    });
  }

  void invoke() {
    List<EditorPart> editors = workbench.getEditors().toList();

    for (EditorPart part in editors) {
      part.save();
    }
  }
}

class EditNextTabAction extends WorkbenchAction {
  EditNextTabAction(Workbench workbench) : super(workbench, "edit-nextTab", "Next Tab") {
    defaultBinding("ctrl-tab");
    macBinding('macCtrl-tab');
  }

  void updateEnabled() {
    enabled = workbench.getEditors().length > 1;
  }

  void invoke() {
    workbench.selectNextTab();
  }
}

class EditPrevTabAction extends WorkbenchAction {
  EditPrevTabAction(Workbench workbench) : super(workbench, "edit-prevTab", "Previous Tab") {
    defaultBinding("ctrl-shift-tab");
    macBinding('macCtrl-shift-tab');
  }

  void updateEnabled() {
    enabled = workbench.getEditors().length > 1;
  }

  void invoke() {
    workbench.selectPreviousTab();
  }
}

class EditGotoLineAction extends EditorAction {
  EditGotoLineAction(Workbench workbench) :
    super(workbench, "edit-gotoLine", "Goto Line...") {
    defaultBinding("ctrl-l");
  }

  void invokeEditor(EditorPart editor) {
    // Use an in-line alert message box, focus the text field, and dismiss the
    // dialog on escape, enter, or clicking the close box.

    BAlert alert = new BAlert().info().closeButton();

    BForm form = new BForm().formInline().compact();
    form.add(new BElement.strong().innerHtml("Goto line"));
    form.add(new BSpan('&nbsp;&nbsp;'));
    BInputElement textField = form.add(new BInputElement().typeText());
    alert.add(form);
    textField.element.onKeyPress.listen((KeyboardEvent event) {
      if (event.keyCode == KeyCode.ESC) {
        event.preventDefault();
        alert.close();
      } else if (event.keyCode == KeyCode.ENTER) {
        event.preventDefault();

        try {
          int line = int.parse(textField.value);

          if (editor is TextEditorPart) {
            (editor as TextEditorPart).gotoLine(line);
            alert.close();
          } else {
            alert.flash();
          }
        } on FormatException catch (e) {
          alert.flash();
        }
      }
    });

    workbench.messageArea.add(alert);

    textField.element.focus();
  }
}

class FileCloseAction extends EditorAction {
  FileCloseAction(Workbench workbench) : super(workbench, "file-close", "Close") {
    defaultBinding("ctrl-w");
  }

  void invokeEditor(EditorPart editor) {
    editor.close();
  }
}

class FileCloseAllAction extends WorkbenchAction {
  FileCloseAllAction(Workbench workbench) : super(workbench, "file-closeAll", "Close All") {
    defaultBinding("ctrl-shift-w");
  }

  void updateEnabled() {
    enabled = !workbench.getEditors().isEmpty;
  }

  void invoke() {
    List<EditorPart> editors = workbench.getEditors().toList();

    for (EditorPart part in editors) {
      part.close();
    }
  }
}

class FileExitAction extends WorkbenchAction {
  FileExitAction(Workbench workbench) : super(workbench, "file-exit", "Quit") {
    macBinding("ctrl-q");
    winBinding("ctrl-shift-f4");
  }

  void invoke() {
    chrome.app.window.current.close();
  }
}

class RunRunAction extends WorkbenchAction {
  RunRunAction(Workbench workbench) : super(workbench, "run-run", "Run") {
    defaultBinding("ctrl-r");
  }

  void invoke() {
    EditorPart editor = workbench.getActiveEditor();

    if (editor != null && editor.name.endsWith(".html")) {
      chrome.app.window.create('launch_page.html', id: 'runWindow',
          bounds: new chrome.Bounds(width: 600, height: 800))
      .then((chrome.AppWindow window) {
        // TODO: send messages to the window so it knows what to run
        //print("new window: ${window}");
      });
    } else {
      beep();
    }
  }
}

class RemoteDebugAction extends WorkbenchAction {
  RemoteDebugAction(Workbench workbench) :
    super(workbench, "run-remoteDebug", "Remote Debug...");

  void invoke() {
    //workbench.messageArea.showInfoAlert("TODO:", 'remote debug dialog');

    // TODO:
    connectVm('127.0.0.1', 5000).then((VmConnection connection) {
      connection.logging = true;
      workbench.messageArea.add(new DebuggerBar(connection));
    });
  }
}

class GlobalSearchAction extends WorkbenchAction {
  Drake drake;

  GlobalSearchAction(this.drake, Workbench workbench) :
    super(workbench, "search-focus", "Search") {

    defaultBinding("ctrl-shift-f");
  }

  void invoke() {
    drake.searchBox.focus();
  }
}

class TestJob extends Job {
  bool indeterminate;

  static int _count = 1;

  TestJob(this.indeterminate) : super("Test job ${_count}") {
    _count++;
  }

  Future<Job> run(ProgressMonitor monitor) {
    Completer completer = new Completer();

    monitor.start(name, indeterminate ? 0 : 4);

    int count = 0;

    new Timer.periodic(new Duration(seconds: 1), (Timer timer) {
      monitor.worked(1);

      count++;

      if (count > 4) {
        timer.cancel();
        monitor.done();
        completer.complete(this);
      }
    });

    return completer.future;
  }
}

