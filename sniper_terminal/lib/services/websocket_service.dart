import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:sniper_terminal/models/signal.dart';
import 'package:sniper_terminal/services/connection_manager.dart';

class WebSocketService {
  // Singleton Pattern
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  final StreamController<Signal> _signalController = StreamController<Signal>.broadcast();
  
  bool _isConnecting = false;
  int _retryCount = 0;
  Timer? _reconnectTimer;
  DateTime? _lastDisconnectionTime;

  Stream<Map<String, dynamic>> get adviceStream => _adviceController.stream;
  Stream<Map<String, dynamic>> get alertStream => _alertController.stream; // NEW
  Stream<Signal> get signalStream => _signalController.stream;
  
  final StreamController<Map<String, dynamic>> _adviceController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _alertController = StreamController<Map<String, dynamic>>.broadcast(); // NEW

  void connect() {
    // 1. Connection Guard
    if (_isConnecting) {
      print('🔒 Connection Guard: Already connecting. Ignoring request.');
      return;
    }
    
    // 2. Debounce (min 3 seconds wait after failure)
    if (_lastDisconnectionTime != null) {
      final timeSince = DateTime.now().difference(_lastDisconnectionTime!);
      if (timeSince.inSeconds < 3) {
        print('⏳ Debounce: Waiting for socket cooldown...');
        return;
      }
    }

    _isConnecting = true;
    _reconnectTimer?.cancel();

    // 3. Resource Cleanup
    if (_channel != null) {
       print('🔌 Closing old socket and clearing file descriptors...');
       _channel!.sink.close();
       _channel = null; 
    }

    try {
      final url = ConnectionManager.getWebSocketUrl('/ws/public');
      print('🔌 Connecting to: $url (Attempt ${_retryCount + 1})');
      
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) {
          _isConnecting = false;
          _retryCount = 0; // Reset on success

            String sanitized = message.replaceAll('}{', '}|{');
            List<String> parts = sanitized.split('|');

            for (String part in parts) {
                try {
                  final data = jsonDecode(part);
                  
                  // ROUTING LOGIC
                  String? type = data['type'];
                  
                  if (type == 'ADVICE') {
                      // Predator Advice (Shield)
                      _adviceController.add(data);
                  } 
                  else if (['WHALE', 'LIQUIDATION', 'ICEBERG', 'WALL', 'SENTIMENT'].contains(type)) {
                      // HUD Alerts
                      _alertController.add(data);
                  }
                  else {
                      // Standard Signal (or unknown)
                      // Only try to parse as Signal if it looks like one (has 'symbol' and 'side' or 'entry')
                      if (data.containsKey('symbol') && (data.containsKey('side') || data.containsKey('entry'))) {
                           final signal = Signal.fromJson(data);
                           _signalController.add(signal);
                      }
                  }
                } catch (e) {
                   print('⚠️ Parse Error (part): $e | raw: $part');
                }
            }
        },
        onError: (error) {
          _isConnecting = false;
          print('❌ WebSocket Error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          _isConnecting = false;
          print('❌ WebSocket Closed');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnecting = false;
      print('❌ Connection Failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _lastDisconnectionTime = DateTime.now();
    
    int delay = 1000 * (1 << _retryCount); // 1s, 2s, 4s...
    if (delay > 30000) delay = 30000;

    print('🔄 Reconnecting in ${delay}ms...');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _retryCount++;
      connect();
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _signalController.close();
  }
}
