
library chrome_socket_test;

import 'dart:async';

import '../packages/unittest/unittest.dart';
import '../lib/chrome_socket.dart';

main() {
  group('chrome_socket', () {
    test('create/destroy', () {
      Future future = ChromeSocket.create(ChromeSocketType.TCP).then((ChromeSocket socket) {
        print(socket);
        
        expect(socket.socketId, greaterThan(0));
        socket.destroy();
      });

      expect(future, completes);
    });
    
    test('read/write', () {
      ChromeSocket _socket;
      
      Future future = ChromeSocket.create(ChromeSocketType.TCP).then((ChromeSocket socket) {
        expect(socket.socketId, greaterThan(0));
        _socket = socket;
        return socket.connect('www.google.com', 80);
      }).then((ChromeSocket socket) {
        String str = 'GET /index.html HTTP/1.1\r\n\r\n';
        
        socket.writeSink.add(str.codeUnits);
        
        return socket.readStream.first;
      }).then((List<int> data) {
        expect(data.length, greaterThan(0));
        String str = new String.fromCharCodes(data);
        print(str);
        _socket.destroy();
      });

      expect(future, completes);
    });
    
//    test('read', () {
//      ChromeSocket _socket;
//      
//      Future future = ChromeSocket.create(ChromeSocketType.TCP).then((ChromeSocket socket) {
//        expect(socket.socketId, greaterThan(0));
//        _socket = socket;
//        return socket.connect('localhost', 1234);
//      }).then((ChromeSocket socket) {
//        String str = 'GET /index.html HTTP/1.1\r\n\r\n';
//        
//        socket.writeSink.add(str.codeUnits);
//        
//        return socket.readStream.toList();
//      }).then((List<List<int>> packets) {
//        expect(packets.length, equals(1));
//        for (List<int> packet in packets) {
//          String str = new String.fromCharCodes(packet);
//          print('[${str.trim()}]');          
//        }
//        _socket.destroy();
//      });
//
//      expect(future, completes);
//    });
  });
}
