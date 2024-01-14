import 'dart:async';
import 'dart:developer';

import 'package:rxdart/rxdart.dart';
import 'package:socket_io_client/socket_io_client.dart';

class SocketChannel {
  final String url;
  late final Socket _socket;
  SocketChannel(this.url) {
    _socket = io(url, OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
  }

  final _outerStreamSubject = BehaviorSubject<dynamic>();

  Stream<dynamic> get stream => _outerStreamSubject.stream;

  StreamSubscription? _streamSubscription;

  void startConnection() {
    _socket.connect();
  }

  void reconnect() {
    startConnection();
  }

  void close() {
    log("close connect to socket server");
    _streamSubscription?.pause();
    _streamSubscription = null;
  }

  String get socketId => _socket.id!;
}

class ConvertChannel extends SocketChannel {
  ConvertChannel(super.url);

  void onConverting(Function(dynamic data) onListen) {
    _socket.on("converting", onListen);
  }
}
//
// socket.onConnect((data) {
// print('socketok: ${data}');
// });
//
// socket.onError((data) {
// print('socketerror');
// print(data);
// });
//
// socket.on('connected', (data) => print("connected: ${data}"));
//
// socket.on("converting", (data) => print("connected: ${data}"));