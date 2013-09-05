
library bootstrap;

import 'dart:async';
import 'dart:html';

import 'utils.dart';

final BootstrapManager bootstrapManager = new BootstrapManager();

Point absoluteOffset(Element element) {
  num left = 0;
  num top = 0;

  while ((element != null) && !(element is BodyElement)) {
    Rect offset = element.offset;

    left += offset.left;
    top += offset.top;

    element = element.parent;
  }

  return new Point(left, top);
}

Element createIcon(String id) {
  return new Element.tag('i')..classes.add(id);
}

class BootstrapManager {
  List<String> getThemes() {
    // bootstrap/css/bootstrap.css
    String themes = i18n('bootstrap_themes');

    return themes.split(',').map((String str) => "bootstrap/css/${str}.css");
  }

  String getTheme() {
    return (query('#bootstrapTheme') as LinkElement).href;
  }

  void setTheme(String theme) {
    (query('#bootstrapTheme') as LinkElement).href = theme;
  }
}

class BElement {
  Element element;

  BElement() {

  }

  BElement.a([Element parent]) {
    element = new Element.tag('a');
    setParent(parent);
  }

  BElement.h3([Element parent]) {
    element = new Element.tag('h3');
    setParent(parent);
  }

  BElement.p([Element parent]) {
    element = new Element.tag('p');
    setParent(parent);
  }

  BElement.strong([Element parent]) {
    element = new Element.tag('strong');
    setParent(parent);
  }

  /**
   * Used by forms.
   */
  BElement.legend([Element parent]) {
    element = new LegendElement();

    setParent(parent);
  }

  /**
   * Used by forms.
   */
  BElement.label([Element parent]) {
    element = new LabelElement();
    setParent(parent);
  }

  BElement.option([Element parent]) {
    element = new OptionElement();
    setParent(parent);
  }

  BElement.tbody([Element parent]) {
    element = new Element.tag('tbody');
    setParent(parent);
  }

  BElement.tr([Element parent]) {
    element = new TableRowElement();
    setParent(parent);
  }

  BElement.td([Element parent]) {
    element = new TableCellElement();
    setParent(parent);
  }

  BElement attribute(String name, String value) {
    element.attributes[name] = value;
    return this;
  }

  BElement clazz(String value) {
    element.classes.add(value);
    return this;
  }

  BElement toggle(String value) {
    element.classes.toggle(value);
    return this;
  }

  BElement alert() {
    return clazz('alert');
  }

  BElement divider() {
    return clazz('divider');
  }

  BElement disabled([bool value = true]) {
    if (value) {
      if (!element.classes.contains('disabled')) {
        element.classes.add('disabled');
      }
    } else {
      if (element.classes.contains('disabled')) {
        element.classes.remove('disabled');
      }
    }

    return this;
  }

  bool get isDisabled => element.classes.contains('disabled');

  BElement dividerVertical() {
    return clazz('divider-vertical');
  }

  BElement dropdown() {
    return clazz('dropdown');
  }

  BElement dropdownMenu() {
    return clazz('dropdown-menu');
  }

  BElement dropdownToggle() {
    return clazz('dropdown-toggle');
  }

  BElement innerHtml(String value) {
    element.innerHtml = value;
    return this;
  }

  BElement nav() {
    return clazz('nav');
  }

  BElement navTabs() {
    return clazz('nav-tabs');
  }

  BElement navbarForm() {
    return clazz('navbar-form');
  }

  BElement navbarSearch() {
    return clazz('navbar-search');
  }

  BElement navbarText() {
    return clazz('navbar-text');
  }

  BElement placeholder(String placeHolder) {
    return attribute('placeholder', placeHolder);
  }

  BElement popover() {
    return clazz('popover');
  }

  BElement role(String value) {
    return attribute('role', value);
  }

  BElement searchQuery() {
    return clazz('search-query');
  }

  /**
   * Used by forms.
   */
  BElement controlGroup() {
    return clazz('control-group');
  }

  /**
   * Used by forms.
   */
  BElement controlLabel() {
    return clazz('control-label');
  }

  /**
   * Used by forms.
   */
  BElement controls() {
    return clazz('controls');
  }

  BElement text(String value) {
    element.text = value;
    return this;
  }

  BElement type(String value) {
    return attribute('type', value);
  }

  BElement width(String val) {
    return style('width', val);
  }

  BElement style(String name, String val) {
    element.style.setProperty(name, val);
    return this;
  }

  BElement pullRight() {
    return clazz('pull-right');
  }

  BElement visibility(bool val) {
    element.style.visibility = val ? 'visible' : 'hidden';
    return this;
  }

  BElement displayNone() {
    element.style.display = 'none';
    return this;
  }

  BElement add(BElement child) {
    element.children.add(child.element);
    return child;
  }

  BElement remove(BElement child) {
    element.children.remove(child.element);
    return child;
  }

  Element addElement(Element el) {
    element.children.add(el);
    return el;
  }

  Element removeElement(Element el) {
    element.children.remove(el);
    return el;
  }

  Element get parent => element.parent;

  setParent(Element p) {
    if (p != null) {
      p.children.add(element);
    }
  }

}

class BButton extends BElement {

  BButton([Element parent]) {
    element = new ButtonElement();
    clazz('btn');
    type('button');

    setParent(parent);
  }

  BButton buttonMini() {
    return clazz('btn-mini');
  }

  BButton buttonPrimary() {
    return clazz('btn-primary');
  }

  BButton close() {
    return clazz('close');
  }
}

class BImage extends BElement {

  BImage([Element parent]) {
    element = new ImageElement();

    setParent(parent);
  }

  BImage src(String src) {
    (element as ImageElement).src = src;
    return this;
  }
}

class BSpan extends BElement {

  BSpan([String html, Element parent]) {
    element = new Element.tag('span');

    setParent(parent);

    if (html != null) {
      innerHtml(html);
    }
  }
}

class BDiv extends BElement {

  BDiv([Element parent]) {
    element = new DivElement();

    setParent(parent);
  }

  BDiv well() {
    return clazz('well');
  }

  BDiv wellSmall() {
    return clazz('well-small');
  }
}

class BInputElement extends BElement {

  BInputElement([Element parent]) {
    element = new InputElement();

    setParent(parent);
  }

  BInputElement checkbox() {
    return type('checkbox');
  }

  BInputElement typeText() {
    return type('text');
  }

  bool get checked => (element as InputElement).checked;

  String get value => (element as InputElement).value;

  set checked(bool value) {
    (element as InputElement).checked = value;
  }
}

class BSelect extends BElement {
  BSelect([Element parent]) {
    element = new SelectElement();

    setParent(parent);
  }

  BElement createOption(String text, [bool selected]) {
    BElement option = add(new BElement.option().text(text));

    if (selected) {
      option.element.attributes['selected'] = '';
      (element as SelectElement).selectedIndex = element.children.length - 1;
    }

    return option;
  }

  String getSelectedItem() {
    SelectElement select = (element as SelectElement);
    return select.item(select.selectedIndex).text;
  }
}

class BTable extends BElement {
  BElement tbody;

  BTable([Element parent]) {
    element = new TableElement();
    clazz('table');

    tbody = add(new BElement.tbody());

    setParent(parent);
  }

  BTable tableStriped() {
    return clazz('table-striped');
  }

  BTable tableBordered() {
    return clazz('table-bordered');
  }

  BTable tableHover() {
    return clazz('table-hover');
  }

  BTable tableCondensed() {
    return clazz('table-condensed');
  }

  BElement createRow() {
    return tbody.add(new BElement.tr());
  }

  BElement createCell(BElement row) {
    return row.add(new BElement.td());
  }
}

class BUnorderedList extends BElement {

  BUnorderedList([Element parent]) {
    element = new Element.tag('ul');

    setParent(parent);
  }

  BUnorderedList navList() {
    return clazz('nav-list');
  }

  BUnorderedList navPills() {
    return clazz('nav-pills');
  }
}

class BListItem extends BElement {

  BListItem([Element parent]) {
    element = new LIElement();

    setParent(parent);
  }

  BListItem toggleActive() {
    return toggle('active');
  }

  BListItem mono() {
    return clazz('mono');
  }

  BListItem navHeader() {
    return clazz('nav-header');
  }
}

class BCloseButton extends BButton {

  BCloseButton([Element parent]) : super(parent) {
    element.classes.remove('btn');
    close();
    innerHtml('&times;');

    element.onClick.listen(_close);
  }

  void _close(MouseEvent event) {
    parent.parent.children.remove(parent);
  }
}

class BMenubar {
  Element _element;
  List<BMenu> menus = new List<BMenu>();

  BMenubar() {
    _element = new BUnorderedList().nav().element;
  }

  Element get element => _element;

  void add(BMenu menu) {
    menus.add(menu);
    menu.menubar = this;

    _element.children.add(menu.element);
  }

  BMenu getMenu(String name) {
    return menus.firstWhere(
        (BMenu menu) => menu.name == name,
        orElse: () => null);
  }

  void closeAll() {
    for (BMenu menu in menus) {
      menu._open = false;
    }
  }
}

class BMenu {
  String name;
  BMenubar menubar;
  Element outerElement;
  Element ulElement;
  List<BMenuItem> _items = new List<BMenuItem>();

  BMenu(this.name) {
    outerElement = new BListItem().dropdown().element;

    Element aElement = new BElement.a(outerElement).role('button').
        dropdownToggle().element;
    aElement.innerHtml = "${name} <b class='caret'></b>";
    aElement.onClick.listen(_toggleOpen);

    // TODO: listen for key events
    ulElement = new BUnorderedList(outerElement).role('menu').
        dropdownMenu().element;
    ulElement.onClick.listen((var event) {
      _open = false;
    });
  }

  BMenuItem add(BMenuItem menuItem) {
    ulElement.children.add(menuItem.element);

    _items.add(menuItem);
  }

  void addSeparator() {
    new BListItem(ulElement).role('presentation').divider();
  }

  bool get _open => outerElement.classes.contains('open');

  set _open(bool value) {
    if (!value) {
      outerElement.classes.remove('open');
    } else if (!_open) {
      if (menubar != null) {
        menubar.closeAll();
      }

      outerElement.classes.add('open');
      ulElement.focus();
    }
  }

  void _toggleOpen(MouseEvent event) {
    _open = !_open;
  }

  Element get element => outerElement;

  List<BMenuItem> get items => _items;

}

class BMenuItem extends BElement {
  var _handler;
  Element _a;

  BMenuItem(String name, [this._handler]) {
    BListItem li = new BListItem().role('presentation');
    BElement a = new BElement.a().role('menuitem').text(name);

    li.add(a);

    element = li.element;
    _a = a.element;

    if (handler != null) {
      element.onClick.listen(handler);
    }
  }

  void setAcceleratorDescription(String desc) {
    new BSpan('&nbsp;&nbsp;&nbsp;&nbsp;${desc}', _a).pullRight();
  }

  void setEnabled(bool value) {
    if (value != enabled) {
      if (value) {
        element.classes.remove('disabled');
      } else {
        element.classes.add('disabled');
      }
    }
  }

  bool get enabled => !element.classes.contains('disabled');

  dynamic get handler => _handler;
}

//<div class="popover bottom show">
//  <div class="arrow"></div>
//  <h3 class="popover-title"></h3>
//  <div class="popover-content"></div>
//</div>
class BPopover {
  Element relativeToElement;
  bool dockLeft;

  Element _mainElement;
  Element _arrowElement;
  Element _titleElement;
  Element _contentElement;

  BPopover(this.relativeToElement,
      {String location: 'bottom', this.dockLeft: true}) {
    _mainElement = new BDiv(document.body).popover().clazz(location).element;
    _arrowElement = new BDiv(_mainElement).clazz('arrow').element;
    _titleElement = new BElement.h3(_mainElement).clazz('popover-title').element;
    _contentElement = new BDiv(_mainElement).clazz('popover-content').element;
  }

  void setTitle(String title) {
    _titleElement.innerHtml = title;
  }

  void setContent(String content) {
    _contentElement.innerHtml = "<p>${content}</p>";
  }

  Element get titleElement => _titleElement;
  Element get contentElement => _contentElement;

  void show() {
    _mainElement.classes.add('show');

    window.setImmediate(() {
      Point offset = absoluteOffset(relativeToElement);

      // main element positioning
      int mainElementWidth = _mainElement.client.width;
      _mainElement.style.top = '${offset.y + relativeToElement.offsetHeight}px';

      // TODO: this calculation needs work
      if (dockLeft) {
        _mainElement.style.left = '${offset.x}px';
      } else {
        _mainElement.style.left =
            '${-278 + offset.x - mainElementWidth + relativeToElement.client.width}px';
      }

      // arrow positioning
      if (dockLeft) {
        _arrowElement.style.left = '20px';
      } else {
        _arrowElement.style.left = '${mainElementWidth - 20}px';
      }
    });
  }

  void hide() {
    _mainElement.classes.remove('show');
  }

  bool get visible => _mainElement.classes.contains('show');

  set width(String cssWidth) {
    _mainElement.style.width = cssWidth;
  }

  void toggleVisibility() {
    if (visible) {
      hide();
    } else {
      show();
    }
  }

  void dispose() {
    _mainElement.parent.children.remove(_mainElement);
  }
}

class BAlert extends BElement {
  Element _titleSpan;
  Element _messageSpan;

  BAlert([Element parent]) {
    element = new DivElement();
    clazz('alert');

    setParent(parent);
  }

  BAlert createTitleMessage() {
    _titleSpan = add(new BElement.strong()).element;
    add(new BSpan('&nbsp;'));
    _messageSpan = add(new BSpan()).element;
    return this;
  }

  BAlert closeButton() {
    add(new BCloseButton());
    return this;
  }

  BAlert title(String title) {
    _titleSpan.innerHtml = title;
    return this;
  }

  BAlert message(String message) {
    _messageSpan.innerHtml = message;
    return this;
  }

  BAlert success() {
    return clazz('alert-success');
  }

  BAlert info() {
    return clazz('alert-info');
  }

  BAlert warning() {
    return this;
  }

  BAlert error() {
    return clazz('alert-error');
  }

  void close() {
    element.parent.children.remove(element);
  }

  void flash() {
    beep();

    String clazz = getAlertKind();

    element.classes.toggle(clazz);
    element.classes.toggle('alert-error');

    new Timer(new Duration(milliseconds: 350), () {
      element.classes.toggle('alert-error');
      element.classes.toggle(clazz);
    });
  }

  String getAlertKind() {
    for (String clazz in element.classes) {
      if (clazz.startsWith('alert-')) {
        return clazz;
      }
    }

    return null;
  }
}

//<div class="progress">
//  <div class="bar" style="width: 60%;"></div>
//</div>
class BProgress extends BElement {
  Element _bar;

  BProgress([Element parent]) {
    element = new DivElement();
    clazz('progress');

    _bar = add(new BDiv().clazz('bar')).element;

    setParent(parent);
  }

  void setIndeterminate(bool inValue) {
    if (inValue) {
      if (!indeterminate) {
        element.classes.addAll(['progress-striped', 'active']);
        value = 100;
      }
    } else {
      element.classes.removeAll(['progress-striped', 'active']);
    }
  }

  bool get indeterminate => element.classes.contains('progress-striped');

  set value(int val) {
    if (val > 100) {
      val = 100;
    }

    _bar.style.width = '${val}%';
  }

  //int get value => int.parse(_bar.style.width);
}

// TODO: model dialogs

//<div class="modal hide fade">
//  <div class="modal-header">
//    <button type="button" class="close" data-dismiss="modal" aria-hidden="true">&times;</button>
//    <h3>Modal header</h3>
//  </div>
//  <div class="modal-body">
//    <p>One fine body…</p>
//  </div>
//  <div class="modal-footer">
//    <a href="#" class="btn">Close</a>
//    <a href="#" class="btn btn-primary">Save changes</a>
//  </div>
//</div>

// TODO: modeless dialogs

class BForm extends BElement {

  BForm([Element parent]) {
    element = new FormElement();

    setParent(parent);
  }

  BForm formSearch() {
    return clazz('form-search');
  }

  BForm formInline() {
    return clazz('form-inline');
  }

  BForm compact() {
    return clazz('form-compact');
  }

  BForm formHorizontal() {
    return clazz('form-horizontal');
  }
}

class BFieldset extends BElement {

  BFieldset([Element parent]) {
    element = new FieldSetElement();

    setParent(parent);
  }
}

class BTabContainer {
  List<BTab> tabs = new List<BTab>();
  Element _element;
  Element _content;
  Element _editorContent;

  BTab _activeTab;

  List<BTabContainerListener> listeners = new List<BTabContainerListener>();

  BTabContainer(Element parent) {
    _element = new BUnorderedList(parent).nav().navTabs().element;
    _content = new BDiv(parent).well().wellSmall().clazz('flex20').element;
    _editorContent = new BDiv(parent).well().wellSmall().clazz('flex20').element;
  }

  BTab add(BTab tab) {
    _element.children.add(tab.headerElement);

    tabs.add(tab);

    tab.headerElement.onClick.listen(_handleActivatedEvent);
    tab.closeButton.onClick.listen(_handleCloseEvent);

    return tab;
  }

  void removeTab(BTab tab) {
    tabs.remove(tab);
    _element.children.remove(tab.headerElement);
  }

  void setActive(BTab tab) {
    if (_activeTab == tab) {
      return;
    }

    if (_activeTab != null) {
      _activeTab._setActive(false);
      _activeTab = null;
    }

    _activeTab = tab;

    if (_activeTab != null) {
      _activeTab._setActive(true);
    }
  }

  BTab createTab() {
    return add(new BTab(""));
  }

  void _handleActivatedEvent(MouseEvent event) {
    event.stopPropagation();

    BTab tab = _tabFor(event);

    if (tab != null) {
      for (BTabContainerListener listener in listeners) {
        listener.focusRequest(tab);
      }
    }
  }

  void _handleCloseEvent(MouseEvent event) {
    event.stopPropagation();

    BTab tab = _tabFor(event);

    if (tab != null) {
      for (BTabContainerListener listener in listeners) {
        listener.closeRequest(tab);
      }
    }
  }

  BTab _tabFor(MouseEvent event) {
    Element target = event.currentTarget;

    for (BTab tab in tabs) {
      if (tab.headerElement == target || tab.closeButton == target) {
        return tab;
      }
    }

    return null;
  }

  Element get element => _element;

  Element get content => _content;

  Element get editorContent => _editorContent;

}

abstract class BTabContainerListener {
  void focusRequest(BTab tab);
  void closeRequest(BTab tab);
}

class BTab {
  String name;

  Element _headerElement;
  Element _dirtyFlag;
  Element _nameElement;
  Element _closeButton;

  BTab(this.name) {
    _headerElement = new BListItem().element;

    Element a = new BElement.a(_headerElement).element;

    _dirtyFlag = new BSpan('&bullet;&nbsp;', a).element;
    _nameElement = new BSpan(name, a).element;
    _closeButton = new BButton(a).close().element;
    _closeButton.children.add(createIcon('icon-remove'));

    setDirty(false);
  }

  void setName(String name) {
    _nameElement.innerHtml = name;
  }

  void _setActive(bool value) {
    if (value) {
      _headerElement.classes.add('active');
    } else {
      _headerElement.classes.remove('active');
    }
  }

  void setDirty(bool value) {
    _dirtyFlag.style.visibility = value ? 'visible' : 'hidden';
  }

  bool get dirty {
    return _dirtyFlag.style.visibility == 'visible';
  }

  Element get headerElement => _headerElement;

  Element get closeButton => _closeButton;

}
