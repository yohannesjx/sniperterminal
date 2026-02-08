import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sniper_terminal/services/connection_manager.dart';

class ApiService {
  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Sets the Exit Target for a specific symbol
  Future<bool> setExitTarget(String symbol, double targetPrice) async {
    try {
      final url = ConnectionManager.getHttpUrl('/api/set-target');
      print('🎯 Setting Target: $symbol @ $targetPrice (URL: $url)');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'symbol': symbol,
          'target': targetPrice,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Target Set Successfully');
        return true;
      } else {
        print('❌ Failed to set target: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Network Error (setExitTarget): $e');
      return false;
    }
  }
}
