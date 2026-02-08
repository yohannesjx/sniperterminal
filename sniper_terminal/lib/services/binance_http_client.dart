import 'package:http/http.dart' as http;

class BinanceHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  static const String _userAgent = "Sniper-Terminal-v1.1";

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Inject User-Agent (Identity)
    request.headers['User-Agent'] = _userAgent;
    request.headers['Content-Type'] = 'application/x-www-form-urlencoded'; // Default for Binance

    // 2. Security Check: RecvWindow
    // We cannot "inject" it here for signed requests without breaking the signature,
    // but we can SERIOUSLY WARN if it's missing.
    if (request.url.host.contains("binance") && request.url.query.contains("signature=")) {
      if (!request.url.query.contains("recvWindow=")) {
        print("⚠️ [SECURITY-INTERCEPTOR] CRITICAL: Signed Request MISSING recvWindow! ${request.url}");
        // Ideally, we could throw here to "Hardening" the app:
        // throw Exception("Security Policy Violation: Missing recvWindow in signed request.");
      }
    }
    
    return _inner.send(request);
  }
}
