
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  Future<void> saveApiCredentials({
    required String apiKey,
    required String apiSecret,
  }) async {
    // Encrypt and store
    await _storage.write(key: 'binance_api_key', value: apiKey);
    await _storage.write(key: 'binance_api_secret', value: apiSecret);
  }

  Future<Map<String, String>?> getApiCredentialsWithAuth() async {
    // 1. Biometric Check (Optional: Require Auth before reading)
    bool authenticated = false;
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (canCheckBiometrics) {
        authenticated = await _localAuth.authenticate(
          localizedReason: 'Scan face/fingerprint to access Trading Keys',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } else {
        authenticated = true; // Fallback if no biometrics
      }
    } on PlatformException catch (e) {
      print("Bio Auth Error: $e");
      authenticated = true; // Fallback for simulators usually
    }

    if (!authenticated) return null;

    // 2. Read Keys
    final apiKey = await _storage.read(key: 'binance_api_key');
    final apiSecret = await _storage.read(key: 'binance_api_secret');

    if (apiKey == null || apiSecret == null) return null;

    return {'apiKey': apiKey, 'apiSecret': apiSecret};
  }
  
  // Quick check without biometrics (e.g., for showing "Connected" status)
  Future<bool> hasCredentials() async {
    final hasKey = await _storage.containsKey(key: 'binance_api_key');
    final hasSecret = await _storage.containsKey(key: 'binance_api_secret');
    return hasKey && hasSecret;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: 'binance_api_key');
    await _storage.delete(key: 'binance_api_secret');
  }
}
