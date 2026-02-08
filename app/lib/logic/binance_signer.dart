
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class BinanceSigner {
  final String _baseUrl = 'https://fapi.binance.com';

  String _sign(String payload, String apiSecret) {
    var key = utf8.encode(apiSecret);
    var bytes = utf8.encode(payload);
    var hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  // Generic Secure Request
  Future<http.Response> sendSignedRequest({
    required String endpoint, // e.g., '/fapi/v1/order'
    required String method,   // 'GET', 'POST', 'DELETE'
    required Map<String, String> params,
    required String apiKey,
    required String apiSecret,
  }) async {
    // 1. Add Timestamp
    params['timestamp'] = DateTime.now().millisecondsSinceEpoch.toString();
    
    // 2. Build Query String
    // Sort params alphabetically? Binance recommends it but usually unnecessary for simple requests if encoded properly.
    // However, for consistency:
    var sortedKeys = params.keys.toList()..sort();
    var queryString = sortedKeys.map((key) => '$key=${params[key]}').join('&');

    // 3. Sign
    var signature = _sign(queryString, apiSecret);
    var fullQuery = '$queryString&signature=$signature';

    var uri = Uri.parse('$_baseUrl$endpoint?$fullQuery');

    // 4. Headers
    var headers = {
      'X-MBX-APIKEY': apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    // 5. Execute
    if (method == 'GET') {
      return await http.get(uri, headers: headers);
    } else if (method == 'POST') {
      return await http.post(uri, headers: headers);
    } else if (method == 'DELETE') {
      return await http.delete(uri, headers: headers);
    }
    
    throw Exception("Unsupported HTTP Method: $method");
  }

  // Helper: Connection Check
  Future<bool> checkConnection(String apiKey, String apiSecret) async {
    try {
      final response = await sendSignedRequest(
        endpoint: '/fapi/v2/account',
        method: 'GET',
        params: {},
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Binance Connection Error: $e");
      return false;
    }
  }
}
