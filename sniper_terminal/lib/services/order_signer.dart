import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sniper_terminal/models/position.dart';
import 'package:sniper_terminal/services/binance_http_client.dart';

class OrderSigner {
  final _storage = const FlutterSecureStorage();
  final _client = BinanceHttpClient(); // Intercepted Client
  
  // Base URLs
  static const _prodUrl = 'https://fapi.binance.com';
  static const _testnetUrl = 'https://testnet.binancefuture.com';

  // Permission URLs
  static const _prodPermissionUrl = 'https://api.binance.com/sapi/v1/account/apiRestrictions';
  static const _testnetPermissionUrl = 'https://testnet.binancefuture.com/fapi/v1/apiRestrictions'; 

  // Precision Cache
  final Map<String, Map<String, double>> _symbolInfo = {};

  Future<void> fetchExchangeInfo() async {
    try {
      final baseUrl = await _baseUrl;
      final response = await _client.get(Uri.parse('$baseUrl/fapi/v1/exchangeInfo'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        for (var sym in data['symbols']) {
          double tickSize = 0.01;
          double stepSize = 0.01;
          for (var filter in sym['filters']) {
            if (filter['filterType'] == 'PRICE_FILTER') {
              tickSize = double.parse(filter['tickSize']);
            } else if (filter['filterType'] == 'LOT_SIZE') {
              stepSize = double.parse(filter['stepSize']);
            }
          }
          _symbolInfo[sym['symbol']] = {
            'tickSize': tickSize,
            'stepSize': stepSize,
          };
        }
        print('✅ [ORDER-SIGNER] Precision Data Loaded');
      }
    } catch (e) {
      print('⚠️ [ORDER-SIGNER] Failed to fetch ExchangeInfo: $e');
    }
  }

  String formatPrice(String symbol, double price) {
    if (!_symbolInfo.containsKey(symbol)) return price.toStringAsFixed(2);
    double tickSize = _symbolInfo[symbol]!['tickSize']!;
    int prec = _getPrecision(tickSize);
    double rounded = (price / tickSize).round() * tickSize;
    return rounded.toStringAsFixed(prec);
  }

  String formatQty(String symbol, double qty) {
    if (!_symbolInfo.containsKey(symbol)) return qty.toStringAsFixed(3);
    if (!qty.isFinite) return "0"; // Safety Guard
    double stepSize = _symbolInfo[symbol]!['stepSize']!;
    int prec = _getPrecision(stepSize);
    // Quantity should ALWAYS be floored (rounded down) to avoid "Insufficient Balance" errors
    double rounded = (qty / stepSize).floor() * stepSize;
    return rounded.toStringAsFixed(prec);
  }

  int _getPrecision(double val) {
    if (val <= 0) return 0;
    String s = val.toString();
    if (s.contains('e')) {
        // Handle scientific notation? For Binance it's usually simple.
        // But 1e-8 = 0.00000001
        return 8; 
    }
    if (s.contains('.')) {
      return s.split('.')[1].length;
    }
    return 0;
  }
  Future<bool> get isTestnet async {
    final val = await _storage.read(key: 'is_testnet');
    return val == 'true';
  }

  Future<void> setEnvironment(bool isTestnet) async {
    await _storage.write(key: 'is_testnet', value: isTestnet.toString());
  }

  Future<String> get _baseUrl async {
    return (await isTestnet) ? _testnetUrl : _prodUrl;
  }

  Future<void> saveKeys(String apiKey, String secretKey) async {
    final prefix = (await isTestnet) ? 'testnet_' : 'prod_'; 
    await _storage.write(key: '${prefix}binance_api_key', value: apiKey.trim());
    await _storage.write(key: '${prefix}binance_secret_key', value: secretKey.trim());
  }

  Future<Map<String, String?>> getKeys() async {
    final prefix = (await isTestnet) ? 'testnet_' : 'prod_';
    return {
      'apiKey': await _storage.read(key: '${prefix}binance_api_key'),
      'secretKey': await _storage.read(key: '${prefix}binance_secret_key'),
    };
  }

  /// Check API Key Permissions
  Future<String> checkPermissions() async {
    final testnet = await isTestnet;
    final keys = await getKeys();
    final apiKey = keys['apiKey']?.trim();
    final secretKey = keys['secretKey']?.trim();

    if (apiKey == null || secretKey == null) {
      return "❌ Keys not found for ${testnet ? 'Testnet' : 'Production'}.";
    }

    final endpoint = testnet 
        ? '$_testnetUrl/fapi/v2/account' 
        : _prodPermissionUrl;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> params = {
      'timestamp': timestamp.toString(),
      'recvWindow': '5000',
    };

    final queryString = Uri(queryParameters: params).query;
    final signature = _sign(queryString, secretKey);
    final finalQuery = '$queryString&signature=$signature';
    final url = Uri.parse('$endpoint?$finalQuery');

    try {
      final response = await _client.get(
        url,
        headers: {'X-MBX-APIKEY': apiKey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (testnet) {
           return "✅ Testnet Connected!\nAccount Alias: ${data['feeTier'] ?? 'User'}"; 
        } else {
           return """
✅ Production Permission Check:
- IP Restricted: ${data['ipRestrict']}
- Futures Enabled: ${data['enableFutures']}
- Reading Enabled: ${data['enableReading']}
""";
        }
      } else {
        final err = jsonDecode(response.body);
        return "❌ Error: ${err['msg']} (Code: ${err['code']})";
      }
    } catch (e) {
      return "❌ Network Error: $e";
    }
  }

  /// Fetch Open Positions
  /// endpoint: GET /fapi/v2/positionRisk
  Future<List<Position>> fetchPositions() async {
    final keys = await getKeys();
    final apiKey = keys['apiKey']?.trim();
    final secretKey = keys['secretKey']?.trim();

    if (apiKey == null || secretKey == null) return [];

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> params = {
      'timestamp': timestamp.toString(),
      'recvWindow': '5000',
    };

    final queryString = Uri(queryParameters: params).query;
    final signature = _sign(queryString, secretKey);
    final finalQuery = '$queryString&signature=$signature';
    
    final baseUrl = await _baseUrl;
    final url = Uri.parse('$baseUrl/fapi/v2/positionRisk?$finalQuery');

    try {
      final response = await _client.get(url, headers: {'X-MBX-APIKEY': apiKey});

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        // Filter only open positions (amt != 0)
        return data
            .map((e) => Position.fromJson(e))
            .where((p) => p.isOpen)
            .toList();
      }
    } catch (e) {
      print("❌ Error fetching positions: $e");
    }
    return [];
  }

  /// Fetch Account Balance (Equity)
  /// endpoint: GET /fapi/v2/account
  Future<double> fetchAccountBalance() async {
    final keys = await getKeys();
    final apiKey = keys['apiKey']?.trim();
    final secretKey = keys['secretKey']?.trim();

    if (apiKey == null || secretKey == null) return 0.0;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> params = {
      'timestamp': timestamp.toString(),
      'recvWindow': '5000',
    };

    final queryString = Uri(queryParameters: params).query;
    final signature = _sign(queryString, secretKey);
    final finalQuery = '$queryString&signature=$signature';
    
    final baseUrl = await _baseUrl;
    final url = Uri.parse('$baseUrl/fapi/v2/account?$finalQuery');

    try {
      final response = await _client.get(url, headers: {'X-MBX-APIKEY': apiKey});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // totalMarginBalance is the Equity (Balance + Unrealized PNL)
        return double.tryParse(data['totalMarginBalance'].toString()) ?? 0.0;
      }
    } catch (e) {
      print("❌ Error fetching balance: $e");
    }
    return 0.0;
  }

  /// Close Position Market
  Future<void> closePosition({required String symbol, required double quantity}) async {
    // To close, we execute an opposing order.
    // However, executeMarketOrder already exists. We can reuse it or call the API directly with REDUCE_ONLY.
    // Let's use executeMarketOrder logic but force reduceOnly.
    // Wait, quantity must be positive.
    
    // Determine side from current position? No, the caller should know.
    // Use executeMarketOrder with reduceOnly=true
    // NOTE: This func is a wrapper, but simpler to just use executeMarketOrder from UI if we know the side.
    // But let's verify.
  }

  /// Signs and executes a Market Order
  Future<Map<String, dynamic>> executeMarketOrder({
    required String symbol,
    required String side,
    required double quantity,
    bool reduceOnly = false,
  }) async {
    final keys = await getKeys();
    final apiKey = keys['apiKey']?.trim();
    final secretKey = keys['secretKey']?.trim();

    if (apiKey == null || secretKey == null) {
      throw Exception('API Keys not found. Please configure in settings.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Query Parameters
    final Map<String, dynamic> params = {
      'symbol': symbol.toUpperCase(),
      'side': side.toUpperCase(),
      'type': 'MARKET',
      'quantity': formatQty(symbol.toUpperCase(), quantity),
      'timestamp': timestamp.toString(),
      'recvWindow': '5000',
    };

    if (reduceOnly) {
      params['reduceOnly'] = 'true';
    }

    // Generate Signature
    final queryString = Uri(queryParameters: params).query;
    final signature = _sign(queryString, secretKey);
    
    // Append Signature
    final finalQuery = '$queryString&signature=$signature';
    final baseUrl = await _baseUrl;
    final url = Uri.parse('$baseUrl/fapi/v1/order?$finalQuery');

    print("🔌 [ORDER-SIGNER] Target: $url");
    print("🔑 [ORDER-SIGNER] key-start: ${apiKey.substring(0, 4)}***");


    final response = await _client.post(
      url,
      headers: {
        'X-MBX-APIKEY': apiKey,
        // Content-Type is handled by Interceptor but good to have explicit
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Order Failed: ${response.body}');
    }
  }

  /// Signs and executes a Limit Order (e.g. Take Profit)
  Future<Map<String, dynamic>> executeLimitOrder({
    required String symbol,
    required String side,
    required double quantity,
    required double price,
    bool reduceOnly = false,
  }) async {
    final keys = await getKeys();
    final apiKey = keys['apiKey']?.trim();
    final secretKey = keys['secretKey']?.trim();

    if (apiKey == null || secretKey == null) {
      throw Exception('API Keys not found. Please configure in settings.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Query Parameters
    final Map<String, dynamic> params = {
      'symbol': symbol.toUpperCase(),
      'side': side.toUpperCase(),
      'type': 'LIMIT',
      'timeInForce': 'GTC', // Good Till Cancel
      'quantity': formatQty(symbol.toUpperCase(), quantity),
      'price': formatPrice(symbol.toUpperCase(), price),
      'timestamp': timestamp.toString(),
      'recvWindow': '5000',
    };

    if (reduceOnly) {
      params['reduceOnly'] = 'true';
    }

    // Generate Signature
    final queryString = Uri(queryParameters: params).query;
    final signature = _sign(queryString, secretKey);
    
    // Append Signature
    final finalQuery = '$queryString&signature=$signature';
    final baseUrl = await _baseUrl;
    final url = Uri.parse('$baseUrl/fapi/v1/order?$finalQuery');

    print("🔌 [ORDER-SIGNER] Limit Order Target: $url");

    final response = await _client.post(
      url,
      headers: {
        'X-MBX-APIKEY': apiKey,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Limit Order Failed: ${response.body}');
    }
  }

  String _sign(String payload, String secretKey) {
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }
}
