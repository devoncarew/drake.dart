
library vm_sample;

import 'dart:io';

import '../lib/debugger_vm.dart';

VmConnection connection;

void main() {
  int port = 5858;
  
  List<String> args = new Options().arguments;
  
  if (args.length == 1) {
    port = int.parse(args[0]);
  }
  
  print('connecting to port $port...');
  
  Socket.connect('127.0.0.1', port).then((Socket socket) {
    print('connected to debug server');
    
    connection = new VmConnection(
        socket.transform(createVmStreamTransformer()), socket);
    connection.logging = true;
    connection.onEvent.listen(
        handleDebuggerEvent,
        onDone: () => print('connection closed'));    
  }).catchError((e) {
    print("unable to connect: $e");
  });
}

void handleDebuggerEvent(VmEvent event) {
  //print(event);
  
  if (event is VmPausedEvent) {
    VmPausedEvent e = event as VmPausedEvent;
    
    if (e.isPaused) {
      connection.getStackTrace(e.isolate).then((VmResponse response) {
        List<VmCallFrame> frames = response.callFrames;
        print(frames);
      });
      connection.resume(e.isolate);
    }
  }
}
