import 'package:flutter/material.dart';
import 'package:sniper_terminal/services/auth_service.dart';
import 'package:sniper_terminal/services/order_signer.dart';

class PermissionChecker {
  static final _auth = AuthService();
  static final _orderSigner = OrderSigner();

  static Future<void> check(
    BuildContext context, {
    required VoidCallback onGranted,
  }) async {
    // 1. Check Login
    if (!_auth.isLoggedIn) {
      // Navigate to Signup Overlay
      final result = await Navigator.pushNamed(context, '/signup');
      if (result != true) return; // Users cancelled or failed
    }

    // 2. Check API Keys
    final keys = await _orderSigner.getKeys();
    if (keys['apiKey'] == null || keys['secretKey'] == null) {
      // Navigate to API Setup
      final result = await Navigator.pushNamed(context, '/settings');
      // We can't easily know if they saved, so we might re-check or just assume they did their best.
      // Ideally Settings returns true on save.
      // For now, let's re-check
       final recheck = await _orderSigner.getKeys();
       if (recheck['apiKey'] == null) return; 
    }

    // 3. Granted
    onGranted();
  }
}
