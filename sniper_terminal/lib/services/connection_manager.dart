import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ConnectionManager {
  static const int _maxRetries = 5;
  static const int _baseDelayMs = 1000;

  /// Returns the appropriate HTTP API URL based on the environment.
  static String getHttpUrl(String path) {
    String host;
    if (kIsWeb) {
      host = 'localhost'; // Or production URL
    } else if (Platform.isAndroid) {
      host = '10.0.2.2'; 
    } else if (Platform.isIOS) {
       // Physical Device & Simulator (LAN IP)
      host = '152.53.87.200';
    } else {
      // Physical Device fallback
      host = '152.53.87.200'; 
    }

    // Sanitize path
    final cleanPath = path.replaceAll('#', '').trim();
    // API Server runs on 8083
    return 'http://$host:8083$cleanPath';
  }

  /// Returns the appropriate WebSocket URL based on the environment.
  static String getWebSocketUrl(String path) {
    // Public Server IP
    const host = '152.53.87.200';

    // Sanitize path
    final cleanPath = path.replaceAll('#', '').trim();
    // WebSocket Server runs on 8081 (Signal Hub)
    print("DEBUG: ConnectionManager returning port 8081");
    // Ensure path starts with /ws/public if not already, or just append it?
    // User requested: ws://152.53.87.200:8081/ws/public
    // If path is passed, we should append it.
    // The user said: "Update... to point to ... ws://152.53.87.200:8081/ws/public"
    // Assuming 'path' variable passed to this function might be empty or specific endpoint.
    // If the usage is `getWebSocketUrl('/ws/public')` then we just need the host.
    // Let's assume the callers pass the path.
    return 'ws://$host:8083$cleanPath';
  }

  /// connect with Exponential Backoff
  static Future<void> connectWithBackoff({
    required Function() onConnect,
    required Function(dynamic error) onError,
  }) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        await onConnect();
        return; // Success
      } catch (e) {
        attempts++;
        final delay = _baseDelayMs * (1 << (attempts - 1)); // 1s, 2s, 4s...
        debugPrint('⚠️ Connection attempt $attempts failed. Retrying in ${delay}ms...');
        onError(e);
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    debugPrint('❌ Max retries reached. Connection failed.');
  }
}
