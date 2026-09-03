import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WifiService {
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Timer? _heartbeatTimer;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get messageStream => _messageController.stream;

  bool get isConnected => _socket != null;

  Future<bool> connect(
    String ip,
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    await disconnect();

    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _connectionController.add(true);

      _subscription = socket.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true).trim();
          if (text.isNotEmpty) {
            _messageController.add(text);
          }
        },
        onError: (_) => _markDisconnected(),
        onDone: _markDisconnected,
        cancelOnError: true,
      );

      _startHeartbeat();

      return true;
    } catch (_) {
      _markDisconnected();
      return false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    // Send one immediately, then keep sending while the controller is alive.
    _sendHeartbeat();

    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _sendHeartbeat(),
    );
  }

  void _sendHeartbeat() {
    final socket = _socket;
    if (socket == null) return;

    try {
      socket.write('C\n');
    } catch (_) {
      _markDisconnected();
    }
  }

  bool send(String command) {
    final socket = _socket;
    if (socket == null) return false;

    try {
      socket.write('$command\n');
      return true;
    } catch (_) {
      _markDisconnected();
      return false;
    }
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final socket = _socket;
    _socket = null;

    if (socket != null) {
      await socket.close();
    }

    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  void _markDisconnected() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _subscription = null;
    _socket = null;

    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionController.close();
    await _messageController.close();
  }
}
