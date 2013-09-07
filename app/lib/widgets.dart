
library drake.widgets;

import 'dart:async';
import 'dart:html';

import 'bootstrap.dart';
import 'utils.dart';

class Action {
  StreamController<Action> streamController = new StreamController<Action>();
  Stream<Action> _stream;

  String id;
  String name;
  bool _enabled = true;

  KeyBinding binding;

  Action(this.id, this.name) {
    _stream = streamController.stream.asBroadcastStream();
  }

  void defaultBinding(String str) {
    if (binding == null) {
      binding = new KeyBinding(str);
    }
  }

  void linuxBinding(String str) {
    if (isLinux()) {
      binding = new KeyBinding(str);
    }
  }

  void macBinding(String str) {
    if (isMac()) {
      binding = new KeyBinding(str);
    }
  }

  void winBinding(String str) {
    if (isWin()) {
      binding = new KeyBinding(str);
    }
  }

  void invoke() {

  }

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled != value) {
      _enabled = value;

      streamController.add(this);
    }
  }

  bool matches(KeyEvent event) {
    return binding == null ? false : binding.matches(event);
  }

  Stream<Action> get onChange => _stream;

  String getBindingDescription() {
    return binding == null ? null : binding.getDescription();
  }

  String toString() {
    return 'Action: ${name}';
  }
}

Map<String, int> _bindingMap = {
  "META": KeyCode.META,
  "CTRL": isMac() ? KeyCode.META : KeyCode.CTRL,
  "MACCTRL": KeyCode.CTRL,
  "ALT": KeyCode.ALT,
  "SHIFT": KeyCode.SHIFT,

  "F1": KeyCode.F1,
  "F2": KeyCode.F2,
  "F3": KeyCode.F3,
  "F4": KeyCode.F4,
  "F5": KeyCode.F5,
  "F6": KeyCode.F6,
  "F7": KeyCode.F7,
  "F8": KeyCode.F8,
  "F9": KeyCode.F9,
  "F10": KeyCode.F10,
  "F11": KeyCode.F11,
  "F12": KeyCode.F12,

  "TAB": KeyCode.TAB
};

class KeyBinding {
  Set<int> modifiers = new Set<int>();
  int keyCode;

  KeyBinding(String str) {
    List<String> codes = str.toUpperCase().split('-');

    for (String str in codes.getRange(0, codes.length - 1)) {
      modifiers.add(_codeFor(str));
    }

    keyCode = _codeFor(codes[codes.length - 1]);
  }

  bool matches(KeyEvent event) {
    if (event.keyCode != keyCode) {
      return false;
    }

    if (event.ctrlKey != modifiers.contains(KeyCode.CTRL)) {
      return false;
    }

    if (event.metaKey != modifiers.contains(KeyCode.META)) {
      return false;
    }

    if (event.altKey != modifiers.contains(KeyCode.ALT)) {
      return false;
    }

    if (event.shiftKey != modifiers.contains(KeyCode.SHIFT)) {
      return false;
    }

    return true;
  }

  String getDescription() {
    List<String> desc = new List<String>();

    if (modifiers.contains(KeyCode.CTRL)) {
      desc.add(_descriptionOf(KeyCode.CTRL));
    }

    if (modifiers.contains(KeyCode.META)) {
      desc.add(_descriptionOf(KeyCode.META));
    }

    if (modifiers.contains(KeyCode.ALT)) {
      desc.add(_descriptionOf(KeyCode.ALT));
    }

    if (modifiers.contains(KeyCode.SHIFT)) {
      desc.add(_descriptionOf(KeyCode.SHIFT));
    }

    desc.add(_descriptionOf(keyCode));

    return desc.join('+');
  }

  int _codeFor(String str) {
    if (_bindingMap[str] != null) {
      return _bindingMap[str];
    }

    return str.codeUnitAt(0);
  }

  String _descriptionOf(int code) {
    if (isMac() && code == KeyCode.META) {
      return "Cmd";
    }

    if (code == KeyCode.META) {
      return "Meta";
    }

    if (code == KeyCode.CTRL) {
      return "Ctrl";
    }

    for (String key in _bindingMap.keys) {
      if (code == _bindingMap[key]) {
        return toTitleCase(key);
      }
    }

    return new String.fromCharCode(code);
  }
}

/**
 * A utility class for working with flex layouts.
 *
 * Ex:
 *
 *     FlexLayout.container.vertical(parent);
 *     FlexLayout.child.grab(child1, 0);
 *     FlexLayout.child.grab(child2, 20);
 *
 * See http://dev.w3.org/csswg/css-flexbox/
 */
class FlexLayout {
  static FlexLayoutContainer container = new FlexLayoutContainer();
  static FlexLayoutChild child = new FlexLayoutChild();
}

class FlexLayoutContainer {

  /**
   * Cause the container to use the flex layout, and lay out its children into
   * columns.
   */
  FlexLayoutContainer vertical(Element container) {
    // display: -webkit-flex;
    // -webkit-flex-direction: column;
    container.style.display = "-webkit-flex";
    container.style.flexDirection = "column";
  }

  /**
   * Cause the container to use the flex layout, and lay out its children into
   * rows.
   */
  FlexLayoutContainer horizontal(Element container) {
    container.style.display = "-webkit-flex";
    container.style.flexDirection = "row";
  }

  FlexLayoutContainer singleLine(Element container) {
    container.style.flexWrap = "nowrap";
  }

  FlexLayoutContainer multiLine(Element container) {
    container.style.flexWrap = "wrap";
  }
}

class FlexLayoutChild {
  /**
   * Assigns the given flex box child a given weight. This is the amount of the
   * un-assigned layout space to grab.
   */
  FlexLayoutChild grab(Element child, int amount) {
    // -webkit-flex: 20;
    child.style.flex = "${amount}";
  }

  FlexLayoutChild minHeight(Element child, String value) {
    child.style.minHeight = value;
  }
}

/**
 * Create a YesNoDialog dialog. It is possible to have more then two buttons
 * by passing in a list of button names in the constructor. An instance of
 * a YesNoDialog can only be used once.
 */
class YesNoDialog extends BAlert {
  Completer _completer = new Completer();

  YesNoDialog(String dialogTitle, String dialogMessage,
      [List buttonText = const ["Yes", "No"]]) {
    createTitleMessage();
    info();
    title(dialogTitle);
    message(dialogMessage);

    BElement closeButton = new BElement.a().clazz('close').innerHtml('&times;');
    add(closeButton);
    closeButton.element.onClick.listen((_) {
      close();
      _completer.complete(-1);
    });

    int count = 0;

    for (String text in buttonText) {
      final _count = count;
      add(new BSpan('&nbsp;'));
      BButton button = new BButton().text(text);
      if (_count == 0) {
        button.buttonPrimary();
      }
      button.element.onClick.listen((_) {
        close();
        _completer.complete(_count);
      });
      add(button);
      count++;
    }
  }

  Future<int> getResponse() {
    return _completer.future;
  }
}

class Selection {
  List selections;

  Selection(Object sel) {
    selections = [sel];
  }

  Selection.fromList(List sel) {
    selections = sel.toList();
  }

  Object get single => selections.length > 0 ? selections.first : null;
}

class SelectionEvent {
  final Selection selection;
  final bool doubleClick;

  SelectionEvent(this.selection, [this.doubleClick]);
}

class TreeLabelProvider<T> {
  void render(TreeItem treeItem, T t) {
    treeItem.span.text = '${t}';
  }
}

abstract class ContentProvider<T> {
  StreamController<T> streamController = new StreamController<T>();
  Stream<T> _stream;

  ContentProvider() {
    _stream = streamController.stream.asBroadcastStream();
  }

  List<T> getRoots(T input);

  bool hasChildren(T node) {
    return false;
  }

  List<T> getChildren(T node);

  Future<T> getParent(T node);

  Stream<T> get onCommand => _stream;

  void notifyChanged(T node) {
    streamController.add(node);
  }

  void dispose() {

  }
}

class TreeViewer {
  BUnorderedList _list;
  List<_TreeViewerSection> _sections = new List<_TreeViewerSection>();
  dynamic _input;

  TreeItem _selectedItem;
  StreamController<SelectionEvent> _streamController = new StreamController<SelectionEvent>();

  TreeLabelProvider labelProvider = new TreeLabelProvider();

  TreeViewer(Element container) {
    _list = new BUnorderedList(container).navList().nav().clazz('treeViewer');
    _list.element.onKeyPress.listen(_handleKeyEvent);
  }

  void addHeader(String text) {
    //<li class="nav-header">Folders</li>
    _list.add(new BListItem().navHeader().text(text));
  }

  void addDivider() {
    _list.add(new BListItem().divider());
  }

  void addContentProvider(ContentProvider contentProvider) {
    _sections.add(new _TreeViewerSection(this, contentProvider));
  }

  void setInput(var input) {
    this._input = input;

    // TODO: clear and recalc everything
    for (_TreeViewerSection section in _sections) {
      section.recalc(input);
    }
  }

  Stream<SelectionEvent> get onSelectionChange => _streamController.stream;

  dynamic get input => _input;
  Element get element => _list.element;

  void _selected(TreeItem item, [bool doubleClick]) {
    if (_selectedItem != null) {
      _selectedItem.selected = false;
      _selectedItem = null;
    }

    _selectedItem = item;
    item.selected = true;

    _streamController.add(
        new SelectionEvent(new Selection(_selectedItem.data), doubleClick));
  }

  void _handleKeyEvent(KeyEvent event) {
    // handle up, down
    if (event.keyCode == KeyCode.UP) {
      _moveSelection(-1);
    } else if (event.keyCode == KeyCode.DOWN) {
      _moveSelection(1);
    }

    // TODO: left, right

    // TODO: space, enter

  }

  void _moveSelection(int direction) {
    if (_selectedItem == null) {
      return;
    }

    int index = _list.element.children.indexOf(_selectedItem.element);
    int length = _list.element.children.length;

    index += direction;

    while (index >= 0 && index < length) {
      Element e = _list.element.children[index];

      if (e.style.display != 'none') {
        // TODO:
        //_selected(_getItem(e));
      }

      index += direction;
    }
  }
}

class TreeItem {
  Element element;
  Object data;
  bool _open = false;
  Element ul;

  TreeItem() {
    element = new LIElement();
    element.children.add(new Element.tag('a'));
    a.children.add(new BSpan('\u25B8 ').element);
    a.children.add(new SpanElement());
    hasContent = false;
  }

  TreeItem.createFrom(this.element);

  Element get a => element.children.first;
  Element get discloseIcon => a.children.first;
  Element get span => a.children[1];

  Element createUL() {
    ul = new BUnorderedList(element).navList().nav().clazz('treeViewer').element;
    return ul;
  }

  bool get hasContent => discloseIcon.style.visibility == 'inherit';

  set hasContent(bool value) {
    if (value) {
      discloseIcon.style.visibility = 'inherit';
    } else {
      discloseIcon.style.visibility = 'hidden';
    }
  }

  set selected(bool value) {
    if (value) {
      element.classes.add('active');
    } else {
      element.classes.remove('active');
    }
  }

  bool get open => _open;

  set open(bool value) {
    _open = value;
    discloseIcon.text = value ? '\u25BE ' : '\u25B8 ';
  }
}

class _TreeViewerSection {
  TreeViewer listViewer;
  ContentProvider contentProvider;

  BListItem start;
  BListItem end;

  _TreeViewerSection(this.listViewer, this.contentProvider) {
    start = new BListItem().displayNone();
    listViewer._list.add(start);

    end = new BListItem().displayNone();
    listViewer._list.add(end);
  }

  void clearAll() {
    int startIndex = _indexOf(start);
    int endIndex = _indexOf(end);

    for (int i = endIndex - 1; i > startIndex; i--) {
      listViewer._list.element.children.removeAt(i);
    }

    // TODO: this hits an unimplemented exception
//    if (endIndex - startIndex > 1) {
//      listViewer._list.element.children.removeRange(startIndex + 1, endIndex);
//    }
  }

  int _indexOf(BListItem item) {
    return listViewer._list.element.children.indexOf(item.element);
  }

  void recalc(var input) {
    // TODO:
    clearAll();

    if (input != null) {
      List items = contentProvider.getRoots(input);

      for (var item in items) {
        TreeItem treeItem = _createTreeItem();
        treeItem.data = item;

        listViewer.labelProvider.render(treeItem, item);

        if (contentProvider.hasChildren(item)) {
          treeItem.hasContent = true;
        }
      }
    }
  }

  void toggleOpen(TreeItem item) {
    if (item.hasContent) {
      item.open = !item.open;

      if (!item.open) {
        // remove all the child content
        item.element.children.remove(item.ul);
      } else {
        // add child content
        item.createUL();

        // TODO: consolidate like code
        for (var child in contentProvider.getChildren(item.data)) {
          TreeItem childItem = _createSubItem(item.ul);
          childItem.data = child;

          listViewer.labelProvider.render(childItem, child);

          if (contentProvider.hasChildren(item)) {
            childItem.hasContent = true;
          }
        }
      }
    }
  }

  TreeItem _createTreeItem() {
    // create the next one right before the 'end' element
    int index = _indexOf(end);
    TreeItem treeItem = new TreeItem();
    listViewer._list.element.children.insert(index, treeItem.element);
    treeItem.element.onClick.listen((MouseEvent e) {
      e.stopImmediatePropagation();
      listViewer._selected(treeItem);
    });
    treeItem.element.onDoubleClick.listen((MouseEvent e) {
      e.stopImmediatePropagation();
      listViewer._selected(treeItem, true);
    });
    treeItem.discloseIcon.onClick.listen((MouseEvent e) {
      e.stopImmediatePropagation();
      toggleOpen(treeItem);
    });
    return treeItem;
  }

  TreeItem _createSubItem(Element ul) {
    TreeItem treeItem = new TreeItem();
    ul.children.add(treeItem.element);
    treeItem.element.onClick.listen((MouseEvent e) {
      e.stopImmediatePropagation();
      listViewer._selected(treeItem);
    });
    treeItem.element.onDoubleClick.listen((MouseEvent e) {
      e.stopImmediatePropagation();
      listViewer._selected(treeItem, true);
    });
    treeItem.discloseIcon.onClick.listen((MouseEvent e) {
      e.stopImmediatePropagation();
      toggleOpen(treeItem);
    });
    return treeItem;
  }
}
