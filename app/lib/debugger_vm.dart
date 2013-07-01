
/**
 * A library to communicate with the standalone Dart VM's debugger.
 */
library debugger_vm;

import 'dart:async';
import 'dart:json' as json;

// TODO: utf8

// TODO: manage a list of breakpoints (per isolate?)

StreamEventTransformer<List<int>, String> createVmStreamTransformer() {
  return new _MessageTransformer();
}

EventSink<String> convertStringToIntSink(EventSink<List<int>> sink) {
  return new _SinkTransformer(sink);
}

class VmConnection {
  Stream<String> _stream;
  EventSink<String> _streamSink;

  int _nextId = 1;
  Map<int, VmIsolate> _commandIsolates = new Map<int, VmIsolate>();
  Map<int, Completer> _commandCompleters = new Map<int, Completer>();
  
  StreamController<VmEvent> _controller = new StreamController<VmEvent>();
  Stream<VmEvent> _eventStream;

  bool logging;
  
  VmIsolate mainIsolate;
  List<VmIsolate> isolates = [];
  
  VmConnection(this._stream, this._streamSink) {
    _stream.listen(
        _handleStreamData,
        onDone: () => _controller.close(),
        cancelOnError: true,
        onError: (error) => _controller.addError(error));
    
    _eventStream = _controller.stream.asBroadcastStream();
  }
  
  Stream<VmEvent> get onEvent => _eventStream;

  Future<VmResponse> resume(VmIsolate isolate) {
    return _resumeOnSuccess(
        isolate,
        _sendCommand(new _JsonEvent('resume'), isolate));
  }

  Future<VmResponse> stepInto(VmIsolate isolate) {
    return _resumeOnSuccess(
        isolate,
        _sendCommand(new _JsonEvent('stepInto'), isolate));
  }

  Future<VmResponse> stepOut(VmIsolate isolate) {
    return _resumeOnSuccess(
        isolate,
        _sendCommand(new _JsonEvent('stepOut'), isolate));
  }
  
  Future<VmResponse> stepOver(VmIsolate isolate) {
    return _resumeOnSuccess(
        isolate,
        _sendCommand(new _JsonEvent('stepOver'), isolate));
  }
  
  Future<VmResponse> interrupt(VmIsolate isolate) {
    return _sendCommand(new _JsonEvent('interrupt'), isolate);
  }
  
  Future<VmResponse> getStackTrace(VmIsolate isolate) {
    Future future = _sendCommand(new _JsonEvent('getStackTrace'), isolate);
    
    return future.then((VmResponse response) {
      return response;
    });
  }
  
  void close() {
    _controller.close();
  }
  
  bool get closed {
    return _controller.isClosed;
  }
  
  Future<VmResponse> _sendCommand(_JsonEvent event, [VmIsolate isolate]) {
    event.id = _nextId++;
    
    if (isolate != null) {
      event.isolate = isolate;
      
      _commandIsolates[event.id] = isolate; 
    }
    
    if (logging) {
      print('==> ${event.toJson()}');
    }
    
    Completer completer = new Completer();
    _commandCompleters[event.id] = completer;
    
    _streamSink.add(event.toJson());
    
    return completer.future;
  }
  
  void _handleStreamData(String data) {
    if (logging) {
      print('<== ${data}');
    }

    _JsonEvent event = new _JsonEvent._fromMap(json.parse(data));
    
    if (event.isNotification) {
      _handleNotification(event);
    } else {
      _handleResponse(event);
    }    
  }
  
  void _handleNotification(_JsonEvent _event) {
    VmEvent event;
    
    if (_event.eventName == 'breakpointResolved') {
      event = new VmBreakpointEvent._fromJson(this, _event);
    } else if (_event.eventName == 'isolate') {
      event = new VmIsolateEvent._fromJson(this, _event);
      
      VmIsolateEvent e = event as VmIsolateEvent;
      
      if (e.isCreated) {
        if (mainIsolate == null) {
          mainIsolate = e.isolate;
        }
        isolates.add(e.isolate);
      } else if (e.isShutdown) {
        e.isolate.destroyed = true;
        isolates.remove(e.isolate);
      }
    } else if (_event.eventName == 'paused') {
      event = new VmPausedEvent._fromJson(this, _event);
      
      VmPausedEvent e = event as VmPausedEvent;
      
      // TODO: resume the isolate on return from a resume() command
      e.isolate.paused = true;      
    } else {
      _controller.addError('unknown event type ${_event.eventName}');
    }
    
    if (event != null) {
      _controller.add(event);
    }
  }
  
  void _handleResponse(_JsonEvent event) {
    // { "id": 51 }
    VmIsolate isolate = _commandIsolates.remove(event.id);
    Completer completer = _commandCompleters.remove(event.id);
    
    VmResponse response = new VmResponse._create(isolate, event);    
    
    if (completer != null) {
      completer.complete(response);
    }
  }
  
  VmIsolate _getCreateIsolate(int id) {
    for (VmIsolate isolate in isolates) {
      if (isolate.id == id) {
        return isolate;
      }
    }
    
    VmIsolate isolate = new VmIsolate(id);
    isolates.add(isolate);
    return isolate;
  }
  
  Future<VmResponse> _resumeOnSuccess(VmIsolate isolate,
      Future<VmResponse> future) {
    return future.then((VmResponse response) {
      if (!response.isError) {
        isolate.paused = false;
        _controller.add(new VmPausedEvent.createResumed(this, isolate));
      }      
      return response;
    });
  }  
}

class VmResponse {
  VmIsolate isolate;
  int id;
  String error;
  Map result;
  
  VmResponse._create(this.isolate, _JsonEvent event) {
    id = event.id;
    error = event.error;
    result = event.result;
  }
  
  bool get isError => error != null;
  
  /**
   * Return a list of [VMCallFrame]s. This is available as response to a
   * [getStackTrace] call.
   */
  List<VmCallFrame> get callFrames {
    if (isError) {
      return [];
    } else {
      return VmCallFrame._createFrames(isolate, result);
    }
  }
  
  String toString() {
    if (isError) {
      return 'response: $id, error: $error';
    } else {
      return 'response: $id';
    }
  }
}

class VmLocation {
  int libraryId;
  String url;
  int tokenOffset;
  
  VmLocation._createFrom(Map map) {
    libraryId = map['libraryId'];
    url = map['url'];
    tokenOffset = map['tokenOffset'];
  }
  
  String toString() => 'location $url:$tokenOffset';
}

class VmIsolate {
  final int id;
  bool paused;
  bool destroyed;
  
  VmIsolate(this.id);
  
  String toString() => 'isolate $id';
}

class VmCallFrame {
  static List<VmCallFrame> _createFrames(VmIsolate isolate, Map map) {
    List frames = [];
    
    for (Map m in map['callFrames']) {
      frames.add(new VmCallFrame._createFrom(isolate, m));
    }
    
    return frames;
  }
  
  String functionName;
  VmLocation location;
  List<VmVariable> locals;
  
  VmCallFrame._createFrom(VmIsolate isolate, Map map) {
    functionName = map['functionName'];
    location = new VmLocation._createFrom(map['location']);
    locals = VmVariable._createVariables(isolate, map['locals']);
  }
  
  String toString() => '$functionName()';
}

abstract class VmRef {
  VmIsolate isolate;
  
  VmRef(this.isolate);
}

class VmVariable extends VmRef {
  static List<VmVariable> _createVariables(VmIsolate isolate, List<Map> maps) {
    List variables = [];
    
    for (Map m in maps) {
      variables.add(new VmVariable._createFrom(isolate, m));
    }
    
    return variables;
  }
  
  String name;
  VmValue value;
  
  VmVariable._createFrom(VmIsolate isolate, Map map): super(isolate) {
    name = map['name'];
    value = new VmValue._createFrom(isolate, map['value']);
  }
  
  String toString() => '$name: $value';
}

class VmValue extends VmRef {
  int objectId;
  int classId;
  
  /**
   * One of:
   * * 'string'
   * * 'number'
   * * 'object'
   * * 'boolean'
   */
  String kind;
  
  String text;
  int length;
  
  VmValue._createFrom(VmIsolate isolate, Map map): super(isolate) {
    objectId = map['objectId'];
    classId = map['classId'];
    kind = map['kind'];
    text = map['text'];
    length = map['length'];
  }
  
  String toString() => '$kind[$objectId]=$text';
}

abstract class VmEvent {
  VmConnection connection;
  String name;
  Map params;
  
  VmEvent(this.connection, this.name) {
    params = {};
  }
  
  VmEvent._fromJson(this.connection, _JsonEvent e) {
    name = e.eventName;
    params = e.params;    
  }
  
  String toString() => "$name: $params";
}

class VmIsolateEvent extends VmEvent {
  // { "event": "isolate", "params": { "reason": "created", "id": 7114 }}
  // { "event": "isolate", "params": { "reason": "shutdown", "id": 7114 }}
  VmIsolate isolate;
  
  VmIsolateEvent._fromJson(VmConnection connection, _JsonEvent event):
    super._fromJson(connection, event) {
    isolate = connection._getCreateIsolate(id);    
  }
  
  bool get isCreated => params['reason'] == 'created';
  bool get isShutdown => params['reason'] == 'shutdown';
  
  int get id => params['id'];
}

class VmPausedEvent extends VmEvent {  
  VmLocation location;
  VmIsolate isolate;
  
  VmPausedEvent._fromJson(VmConnection connection, _JsonEvent event):
    super._fromJson(connection, event) {
    isolate = connection._getCreateIsolate(_isolateId);
    location = new VmLocation._createFrom(params['location']);
  }
  
  VmPausedEvent.createResumed(VmConnection connection, VmIsolate isolate):
    super(connection, 'resumed') {
    this.isolate = isolate;
    params['isolateId'] = isolate.id;
  }
  
  bool get isPaused => name == 'paused';
  bool get isResumed => name == 'resumed';
  
  /** 'breakpoint', 'exception', 'interrupted', 'unknown' */
  String get reason => params['reason'];
  // TODO: exception params['exception'] == vmvalue
  
  int get _isolateId => params['isolateId'];
}

class VmBreakpointEvent extends VmEvent {
  VmLocation location;
  VmIsolate isolate;
  
  VmBreakpointEvent._fromJson(VmConnection connection, _JsonEvent event):
    super._fromJson(connection, event) {
    isolate = connection._getCreateIsolate(_isolateId);
    location = new VmLocation._createFrom(params['location']);
  }
  
  int get breakpointId => params['breakpointId'];
  
  int get _isolateId => params['isolateId'];
  
  String toString() => 'breakpointResolved: $breakpointId';
}

class _JsonEvent {
  Map _map;
  
  _JsonEvent(String command) {
    _map = {'command': command};
  }
  
  _JsonEvent._fromMap(Map map) {
    _map = map;
  }
  
  String get command => _map['command'];
  String get eventName => _map['event'];
  
  int get id => _map['id'];
  
  set id(int value) {
    _map['id'] = value;
  }
  
  set isolate(VmIsolate isolate) {
    addParam('isolateId', isolate.id);
  }
  
  bool get isNotification => !_map.containsKey('id');
  
  bool get hasError => _map.containsKey('error');
  String get error => _map['error'];
  
  Map get params => _map['params'];
  
  Map get result => _map['result'];
  
  void addParam(String key, Object value) {
    if (_map['params'] == null) {
      _map['params'] = {};
    }
    
    params[key] = value;
  }
  
  String toJson() => json.stringify(_map);
  
  String toString() => toJson();
}

class _MessageTransformer extends StreamEventTransformer<List<int>, String> {
  List<int> _buffer = new List();
  
  void handleData(List<int> data, EventSink<String> sink) {
    _buffer.addAll(data);    
    
    while(_tryFlush(sink)) {
      
    }
  }
  
  bool _tryFlush(EventSink<String> sink) {
    if (_buffer.isEmpty) {
      return false;
    }
    
    if (_buffer[0] != 123) { // '{'
      sink.addError('unbalanced braces');
      _buffer.clear();
      return false;
    }
    
    int braceCount = 0;
    
    for (int i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 123) { // '{'
        braceCount++;
      } else if (_buffer[i] == 125) { // '}'
        braceCount--;
        
        if (braceCount == 0) {
          sink.add(new String.fromCharCodes(_buffer.getRange(0, i + 1)));
          _buffer.removeRange(0, i + 1);
          return true;
        }
      }
    }
    
    return false;
  }
}

class _SinkTransformer extends EventSink<String> {
  EventSink<List<int>> sink;
  
  _SinkTransformer(this.sink);
  
  void add(String event) {
    // TODO: to utf8
    sink.add(event.codeUnits);
  }

  void addError(error) {
    sink.addError(error);
  }

  void close() {
    sink.close();
  }
}
