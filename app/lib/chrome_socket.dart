
library chrome_socket;

import 'dart:async';

import '../packages/js/js.dart' as js;
import '../packages/js/js_wrapping.dart' as js_wrapping;

// TODO: server socket

final CSocket socket = new CSocket();

dynamic get _chrome => js.context.chrome;

String get _lastError {
  js.Proxy error = _chrome.runtime['lastError'];

  if (error != null) {
    return error['message'];
  } else {
    return null;
  }
}

/**
 * A straight mapping to the chrome.socket APIs.
 */
class CSocket {
  
}

/**
 * One of [TCP] or [UDP].
 */
class ChromeSocketType {
  static final ChromeSocketType TCP = new ChromeSocketType._create('tcp');
  static final ChromeSocketType UDP = new ChromeSocketType._create('udp');
  
  final String value;
  
  const ChromeSocketType._create(this.value);
}

/**
 * Use the chrome.socket module to send and receive data over the network using
 * TCP and UDP connections.
 */
class ChromeSocket {
  
  /**
   * Creates a socket of the specified type.
   */
  static Future<ChromeSocket> create(ChromeSocketType type) {
    // chrome.socket.create(SocketType type, object options, function callback)
    return js.scoped(() {
      Completer completer = new Completer();
      
      js.Callback callback = new js.Callback.once((var result) {
        if (_lastError != null) {
          completer.completeError(_lastError);              
        } else {
          completer.complete(new ChromeSocket._create(result.socketId));
        }
      });
      
      _chrome.socket.create(type.value, callback);
      
      return completer.future;          
    });
  }
  
  int socketId;
  bool disconnected;
  bool destroyed;

  StreamController<List<int>> _readController;
  
  ChromeSocket._create(this.socketId);
  
  /**
   * Connects the socket to the remote machine (for a tcp socket). For a udp
   * socket, this sets the default address which packets are sent to and read
   * from for read() and write() calls.
   */
  Future<ChromeSocket> connect(String hostname, int port) {
    // chrome.socket.connect(integer socketId, string hostname, integer port, function callback)
    return js.scoped(() {
      Completer completer = new Completer();
      
      js.Callback callback = new js.Callback.once((var result) {
        if (_lastError != null) {
          completer.completeError(_lastError);              
        } else {
          completer.complete(this);
        }
      });
      
      _chrome.socket.connect(socketId, hostname, port, callback);
      
      return completer.future;          
    });
  }
  
  /**
   * Return a [Stream] of input data from this socket. This method can only be
   * called once.
   */
  Stream<List<int>> get readStream {
    if (_readController != null) {
      throw new StateError('a read stream has already been created');
    }
    
    _readController = new StreamController<List<int>>();
    _startReading();
    
    return _readController.stream;
  }
  
  /**
   * Return an [EventSink] to write data to this socket.
   */
  EventSink<List<int>> get writeSink {
    return new _ChromeWriteSink(this);
  }
  
  /**
   * Disconnects the socket. For UDP sockets, disconnect is a non-operation but
   * is safe to call.
   */
  void disconnect() {
    if (!disconnected) {
      disconnected = true;
      
      _chrome.socket.disconnect(socketId);
      
      _readController.close();
    }    
  }
  
  /**
   * Destroys the socket. Each socket created should be destroyed after use.
   */
  void destroy() {
    if (!destroyed) {
      destroyed = true;
      
      _chrome.socket.destroy(socketId);
      
      if (!disconnected && _readController != null) {
        _readController.close();
      }
    }
  }
  
  Future<List<int>> _read() {
    // TODO:
    
  }
  
  Future<ChromeSocket> _write(List<int> data) {
    // chrome.socket.write(integer socketId, arraybuffer data, function callback)
    return js.scoped(() {
      Completer completer = new Completer();
      
      js.Callback callback = new js.Callback.once((var result) {
        if (_lastError != null) {
          completer.completeError(_lastError);              
        } else {
          completer.complete(this);
        }
      });
      
      var int8View = new js.Proxy(js.context.Int8Array, js.array(data));
      
      _chrome.socket.write(socketId, int8View.buffer, callback);
      
      return completer.future;
    });
  }
  
  void _startReading() {
    // chrome.socket.read(integer socketId, integer bufferSize, function callback)
    return js.scoped(() {
      js.Callback callback;
      
      callback = new js.Callback.many((var readInfo) {
        int resultCode = readInfo.resultCode;
        var data = readInfo.data; // arraybuffer
        
        //print('resultCode=$resultCode, read length=${data.byteLength}');
        
        if (_lastError != null) {
          //print("error=$_lastError");
          
          if (!disconnected && !destroyed) {
            _readController.addError(_lastError);
          }
        } else if (resultCode < 0) {
          // maybe an error, maybe a closed stream?
          _closeRead();
        } else {
          var int8View = new js.Proxy(js.context.Int8Array, data);
          List<int> result = new List<int>(int8View.length);
          
          for (int i = 0; i < result.length; i++) {
            result[i] = int8View[i];
          }
          
          _readController.add(result);
          
          if (!disconnected && !destroyed) {
            _chrome.socket.read(socketId, 8192, callback);
          }
        }
      });
      
      _chrome.socket.read(socketId, 8192, callback);
    });    
  }
  
  void _closeRead() {
    if (_readController != null) {
      _readController.close();
    }
  }
  
  String toString() => 'socket[$socketId]';
}

class _ChromeWriteSink extends EventSink<List<int>> {
  ChromeSocket socket;
  
  _ChromeWriteSink(this.socket);

  void add(List<int> data) {
    socket._write(data);
  }

  void addError(errorEvent) {
    // TODO: anything to do here?
    
  }

  void close() {
    socket.disconnect();
  }
}
