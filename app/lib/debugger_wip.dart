
library drake.debugger_wip;

import 'dart:async';
import 'dart:json' as json;

class WipConnection {
  Stream<String> _stream;
  StreamSink<String> _streamSink;

  int _nextId = 0;

  WipConsole console;
  WipDebugger debugger;
  WipPage page;
  WipRuntime runtime;

  Map _domains = {};

  StreamController<WipEvent> _streamController = new StreamController<WipEvent>();
  Stream<WipEvent> _notificationStream;

  WipConnection(this._stream, this._streamSink) {
    console = new WipConsole(this);
    debugger = new WipDebugger(this);
    page = new WipPage(this);
    runtime = new WipRuntime(this);

    _stream.listen((String data) {
      _JsonEvent event = new _JsonEvent._fromMap(json.parse(data));

      if (event.isNotification) {
        _handleNotification(event);
      } else {
        _handleResponse(event);
      }
    });

    _notificationStream = _streamController.stream.asBroadcastStream();
  }

  Stream<WipEvent> get onNotification => _notificationStream;

  void _registerDomain(String domainId, WipDomain domain) {
    _domains[domainId] = domain;
  }

  void _sendEvent(_JsonEvent event) {
    event.id = (_nextId++).toString();

    _streamSink.add(event.toJson());
  }

  void _handleNotification(_JsonEvent event) {
    String domainId = event.method;
    int index = domainId.indexOf('.');
    if (index != -1) {
      domainId = domainId.substring(index + 1);
    }
    if (_domains.containsKey(domainId)) {
      _domains[domainId]._handleNotification(event);
    } else {
      _log('unhandled event notification: ${event.method}');
    }
  }

  void _handleResponse(_JsonEvent event) {
    // TODO:

  }

  void _log(String str) {
    print(str);
  }
}

class WipEvent {
  String method;
  Map params;

  WipEvent(this.method, [this.params]);
}

abstract class WipDomain {
  WipConnection connection;

  WipDomain(this.connection);

  void _handleNotification(_JsonEvent event);
}

class WipConsole extends WipDomain {
  WipConsole(WipConnection connection): super(connection) {
    connection._registerDomain('Console', this);
  }

  void enable() {
    connection._sendEvent(new _JsonEvent('Console.enable'));
  }

  void disable() {
    connection._sendEvent(new _JsonEvent('Console.disable'));
  }

  void clearMessages() {
    connection._sendEvent(new _JsonEvent('Console.clearMessages'));
  }

  void _handleNotification(_JsonEvent event) {
    String method = event.method;

    if (method == 'Console.messageAdded') {
      connection._streamController.add(new WipEvent(method, event.params));
    } else {
      connection._streamController.add(new WipEvent(method, event.params));
    }
  }
}

/**
 * Fired by Console.messageAdded.
 */
class WipConsoleMessage extends _WipStructure {
  WipConsoleMessage(Map params): super(params);

  String get text => params['text'];
  String get level => params['level'];
  String get url => params['url'];
  int get repeatCount => params['repeatCount'];
}

class WipDebugger extends WipDomain {
  WipDebugger(WipConnection connection): super(connection) {
    connection._registerDomain('Debugger', this);
  }

  void enable() {
    connection._sendEvent(new _JsonEvent('Debugger.enable'));
  }

  void disable() {
    connection._sendEvent(new _JsonEvent('Debugger.disable'));
  }

  void pause() {
    connection._sendEvent(new _JsonEvent('Debugger.pause'));
  }

  void resume() {
    connection._sendEvent(new _JsonEvent('Debugger.resume'));
  }

  void stepInto() {
    connection._sendEvent(new _JsonEvent('Debugger.stepInto'));
  }

  void stepOut() {
    connection._sendEvent(new _JsonEvent('Debugger.stepOut'));
  }

  void stepOver() {
    connection._sendEvent(new _JsonEvent('Debugger.stepOver'));
  }

  /**
   * State should be one of "all", "none", or "uncaught".
   */
  void setPauseOnExceptions(String state) {
    connection._sendEvent(
        new _JsonEvent('Debugger.setPauseOnExceptions')
          ..addParam('state', state));
  }

  void _handleNotification(_JsonEvent event) {
    // Debugger.paused
    // Debugger.resumed
    connection._streamController.add(new WipEvent(event.method, event.params));
  }
}

class WipDebuggerPaused extends _WipStructure {
  WipDebuggerPaused(Map params): super(params);

  String get reason => params['reason'];
  Object get data => params['data'];

  Iterable<WipCallFrame> get callFrames {
    return params['callFrames'].map((frame) => new WipCallFrame(frame));
  }
}

class WipDebuggerScriptParsed extends _WipStructure {
  WipDebuggerScriptParsed(Map params): super(params);

  String get scriptId => params['scriptId'];
  String get url => params['url'];
  int get startLine => params['startLine'];
  int get startColumn => params['startColumn'];
  int get endLine => params['endLine'];
  int get endColumn => params['endColumn'];
  bool get isContentScript => params['isContentScript'];
  String get sourceMapURL => params['sourceMapURL'];
}

class WipCallFrame extends _WipStructure {
  WipCallFrame(Map params): super(params);

  String get callFrameId => params['callFrameId'];
  String get functionName => params['functionName'];
  WipLocation get location => new WipLocation(params['location']);
  WipRemoteObject get thisObject => new WipRemoteObject(params['this']);
  Iterable<WipScope> get scopeChain {
    return params['scopeChain'].map((scope) => new WipScope(scope));
  }
}

class WipLocation extends _WipStructure {
  WipLocation(Map params): super(params);

  int get columnNumber => params['columnNumber'];
  int get lineNumber => params['lineNumber'];
  String get scriptId => params['scriptId'];
}

class WipScope extends _WipStructure {
  WipScope(Map params): super(params);

  // "catch", "closure", "global", "local", "with"
  String get scope => params['scope'];

  /**
   * Object representing the scope. For global and with scopes it represents the
   * actual object; for the rest of the scopes, it is artificial transient
   * object enumerating scope variables as its properties.
   */
  WipRemoteObject get object => new WipRemoteObject(params['object']);
}

class WipPage extends WipDomain {
  WipPage(WipConnection connection): super(connection) {
    connection._registerDomain('Page', this);
  }

  void enable() {
    connection._sendEvent(new _JsonEvent('Page.enable'));
  }

  void disable() {
    connection._sendEvent(new _JsonEvent('Page.disable'));
  }

  void navigate(String url) {
    connection._sendEvent(
        new _JsonEvent('Page.navigate')..addParam('url', url));
  }

  void reload({bool ignoreCache, String scriptToEvaluateOnLoad}) {
    _JsonEvent event = new _JsonEvent('Page.navigate');

    if (ignoreCache != null) {
      event.addParam('ignoreCache', ignoreCache);
    }

    if (scriptToEvaluateOnLoad != null) {
      event.addParam('scriptToEvaluateOnLoad', scriptToEvaluateOnLoad);
    }

    connection._sendEvent(event);
  }

  void _handleNotification(_JsonEvent event) {
    // Page.loadEventFired
    // Page.domContentEventFired
    connection._streamController.add(new WipEvent(event.method, event.params));
  }
}

class WipRuntime extends WipDomain {
  WipRuntime(WipConnection connection): super(connection) {
    connection._registerDomain('Page', this);
  }

  void _handleNotification(_JsonEvent event) {
    connection._streamController.add(new WipEvent(event.method, event.params));
  }
}

class WipRemoteObject extends _WipStructure {
  WipRemoteObject(Map params): super(params);

  String get className => params['className'];
  String get description => params['description'];
  String get objectId => params['objectId'];
  String get subtype => params['subtype'];
  String get type => params['type'];
  Object get value => params['value'];
}

class _WipStructure {
  Map params;

  _WipStructure(this.params);
}

class _JsonEvent {
  Map _map;

  _JsonEvent(String method) {
    _map = {'method': method};
  }

  _JsonEvent._fromMap(Map map) {
    _map = map;
  }

  String get method => _map['method'];

  String get id => _map['id'];

  set id(String value) {
    _map['id'] = value;
  }

  bool get isNotification => !_map.containsKey('id');

  bool get hasError => _map.containsKey('error');
  Object get error => _map['error'];

  Map get params => _map['params'];

  void addParam(String key, Object value) {
    _map[key] = value;
  }

  String toJson() => json.stringify(_map);
}
