import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

/// BiometricService - Handles FaceID/TouchID authentication for trade execution
class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  /// Check if biometrics are available on this device
  Future<bool> isBiometricsAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }
  
  /// Get list of available biometric types (FaceID, TouchID, Fingerprint)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }
  
  /// Authenticate user before allowing trade execution
  /// Returns true if authentication succeeds, false otherwise
  Future<bool> authenticateForTradeExecution() async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        // Biometrics not available, allow execution
        return true;
      }
      
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to execute trade',
      );
    } on PlatformException catch (e) {
      print('⚠️ [BIOMETRIC] Authentication error: ${e.message}');
      return false;
    } catch (e) {
      print('⚠️ [BIOMETRIC] Unexpected error: $e');
      return false;
    }
  }
  
  /// Authenticate user for sensitive settings (e.g., Burn Terminal)
  Future<bool> authenticateForSensitiveAction(String action) async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        // Biometrics not available, allow action
        return true;
      }
      
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to $action',
      );
    } on PlatformException catch (e) {
      print('⚠️ [BIOMETRIC] Authentication error: ${e.message}');
      return false;
    } catch (e) {
      print('⚠️ [BIOMETRIC] Unexpected error: $e');
      return false;
    }
  }
  
  /// Check if device supports FaceID specifically
  Future<bool> supportsFaceID() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.face);
  }
  
  /// Check if device supports TouchID/Fingerprint specifically
  Future<bool> supportsTouchID() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.fingerprint);
  }
}
