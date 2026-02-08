import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sniper_terminal/services/time_sync_service.dart';
import 'package:sniper_terminal/services/order_signer.dart';

/// SystemHealthService - Monitors critical system components
class SystemHealthService {
  final String _backendUrl;
  final TimeSyncService _timeSyncService = TimeSyncService();
  final OrderSigner _orderSigner = OrderSigner();
  
  // Health status for each component
  bool _scannerHubConnected = false;
  bool _exchangeApiHealthy = false;
  bool _authStateValid = false;
  bool _timeSyncHealthy = false;
  
  // Latency metrics
  int _backendLatencyMs = 0;
  int _exchangeLatencyMs = 0;
  
  // Periodic check timer
  Timer? _healthCheckTimer;
  
  // Callbacks for UI updates
  Function(SystemHealthStatus)? onHealthUpdate;
  
  SystemHealthService({required String backendUrl}) : _backendUrl = backendUrl;
  
  /// Start periodic health checks (every 5 seconds)
  void startMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkAllSystems();
    });
    
    // Initial check
    checkAllSystems();
  }
  
  /// Stop health monitoring
  void stopMonitoring() {
    _healthCheckTimer?.cancel();
  }
  
  /// Check all system components
  Future<void> checkAllSystems() async {
    await Future.wait([
      _checkScannerHub(),
      _checkExchangeApi(),
      _checkAuthState(),
      _checkTimeSync(),
    ]);
    
    // Notify listeners
    if (onHealthUpdate != null) {
      onHealthUpdate!(getCurrentStatus());
    }
  }
  
  /// Check Scanner Hub (WebSocket connection to Go Backend)
  Future<void> _checkScannerHub() async {
    try {
      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse('$_backendUrl/ping'),
      ).timeout(const Duration(seconds: 3));
      
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _scannerHubConnected = data['status'] == 'online'; // Updated to 'online'
        _backendLatencyMs = latency;
        
        // Sync API Status from Backend
        if (data.containsKey('binance_api')) {
           bool isValid = data['binance_api'] == 'valid';
           _exchangeApiHealthy = isValid; // Trust server's validation
           print('🔍 Backend Reports Binance API: ${data['binance_api']}');
        }
      } else {
        _scannerHubConnected = false;
      }
    } catch (e) {
      print('⚠️ [HEALTH] Scanner Hub check failed: $e');
      _scannerHubConnected = false;
      _backendLatencyMs = 0;
    }
  }
  
  /// Check Exchange API (Trust Backend Status)
  Future<void> _checkExchangeApi() async {
    // We now rely 100% on the backend's report from /ping
    // The backend checks strictly every 120s.
    // If backend says 'valid', we are good.
    // If backend says 'limited', we show error.
    
    // Logic moved to _checkScannerHub where we parse 'binance_api' from JSON.
    // This function is now a placeholder or can be removed, but kept for interface consistency.
    if (_scannerHubConnected && _exchangeApiHealthy) {
        _exchangeLatencyMs = _backendLatencyMs; // Approximation
    } else {
        _exchangeLatencyMs = 0;
    }
  }
  
  /// Check Auth State (Verify API keys are loaded and valid)
  Future<void> _checkAuthState() async {
    try {
      final result = await _orderSigner.checkPermissions();
      _authStateValid = result.contains('✅') && result.contains('Futures');
    } catch (e) {
      print('⚠️ [HEALTH] Auth state check failed: $e');
      _authStateValid = false;
    }
  }
  
  /// Check Time Sync (Device clock vs NTP)
  Future<void> _checkTimeSync() async {
    try {
      final offset = await TimeSyncService.checkTimeOffset();
      _timeSyncHealthy = offset != -1 && offset < 1000; // Within 1 second
    } catch (e) {
      print('⚠️ [HEALTH] Time sync check failed: $e');
      _timeSyncHealthy = false;
    }
  }
  
  /// Get current system health status
  SystemHealthStatus getCurrentStatus() {
    return SystemHealthStatus(
      scannerHubConnected: _scannerHubConnected,
      exchangeApiHealthy: _exchangeApiHealthy,
      authStateValid: _authStateValid,
      timeSyncHealthy: _timeSyncHealthy,
      backendLatencyMs: _backendLatencyMs,
      exchangeLatencyMs: _exchangeLatencyMs,
      lastCheckTime: DateTime.now(),
    );
  }
  
  /// Check if all systems are operational
  bool get isAllSystemsGo {
    return _scannerHubConnected && 
           _exchangeApiHealthy && 
           _authStateValid && 
           _timeSyncHealthy;
  }
  
  /// Get failure reason for UI display
  String getFailureReason() {
    final failures = <String>[];
    
    if (!_scannerHubConnected) {
      failures.add('Scanner Hub offline (Backend unreachable)');
    }
    if (!_exchangeApiHealthy) {
      failures.add('Exchange API unavailable (Binance unreachable)');
    }
    if (!_authStateValid) {
      failures.add('Auth State invalid (Check API keys in Settings)');
    }
    if (!_timeSyncHealthy) {
      failures.add('Time Sync failed (Device clock out of sync)');
    }
    
    return failures.isEmpty ? 'All systems operational' : failures.join('\n');
  }
}

/// System Health Status data class
class SystemHealthStatus {
  final bool scannerHubConnected;
  final bool exchangeApiHealthy;
  final bool authStateValid;
  final bool timeSyncHealthy;
  final int backendLatencyMs;
  final int exchangeLatencyMs;
  final DateTime lastCheckTime;
  
  SystemHealthStatus({
    required this.scannerHubConnected,
    required this.exchangeApiHealthy,
    required this.authStateValid,
    required this.timeSyncHealthy,
    required this.backendLatencyMs,
    required this.exchangeLatencyMs,
    required this.lastCheckTime,
  });
  
  bool get isAllHealthy {
    return scannerHubConnected && 
           exchangeApiHealthy && 
           authStateValid && 
           timeSyncHealthy;
  }
}
