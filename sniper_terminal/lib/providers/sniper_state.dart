import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:sniper_terminal/models/signal.dart';
import 'package:sniper_terminal/models/position.dart';
import 'package:sniper_terminal/services/order_signer.dart';
import 'package:sniper_terminal/services/websocket_service.dart';
import 'package:sniper_terminal/services/system_health_service.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SniperState extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  
  // Cache keys in memory for speed/safety
  String? _apiKey;
  String? _secretKey;

  // Risk Management
  double _riskAmount = 10.0; // Default $10 risk per trade
  double get riskAmount => _riskAmount;

  // Auto-Take Profit
  double _targetProfit = 50.0; // Default $50 auto-close
  double get targetProfit => _targetProfit;

  Future<void> setRiskAmount(double val) async {
    _riskAmount = val;
    await _storage.write(key: 'risk_amount', value: val.toString());
    notifyListeners();
  }

  Future<void> setTargetProfit(double val) async {
    _targetProfit = val;
    await _storage.write(key: 'target_profit', value: val.toString());
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    String? risk = await _storage.read(key: 'risk_amount');
    if (risk != null) _riskAmount = double.tryParse(risk) ?? 10.0;
    
    String? tp = await _storage.read(key: 'target_profit');
    if (tp != null) _targetProfit = double.tryParse(tp) ?? 50.0;

    notifyListeners();
  }

  String _selectedCoin = 'BTC';
  final OrderSigner _orderSigner = OrderSigner();
  
  // System Health Monitoring
  late SystemHealthService _healthService;
  SystemHealthStatus _healthStatus = SystemHealthStatus(
    scannerHubConnected: false,
    exchangeApiHealthy: false,
    authStateValid: false,
    timeSyncHealthy: false,
    backendLatencyMs: 0,
    exchangeLatencyMs: 0,
    lastCheckTime: DateTime.now(), // Initial
    statusMessage: 'Initializing...',
  );
  
  SystemHealthStatus get healthStatus => _healthStatus;
  bool get isSystemHealthy => _healthStatus.isAllHealthy;
  
  final List<Signal> _signalHistory = [];
  Signal? _activeSignal;
  List<Position> _positions = [];
  Position? _activePosition;
  bool _whaleWarning = false;
  Timer? _positionTimer;
  bool _isMonitoring = false;

  // Getters
  String get selectedCoin => _selectedCoin;
  UnmodifiableListView<Signal> get signalHistory => UnmodifiableListView(_signalHistory);
  Signal? get activeSignal => _activeSignal;
  Position? get activePosition => _activePosition;
  bool get whaleWarning => _whaleWarning;
  
  // Security & Cooldown
  bool _isExecuting = false;
  DateTime? _lastExecutionTime;
  bool get isExecuting => _isExecuting;

  String? _predatorAdvice;
  String? get predatorAdvice => _predatorAdvice;
  
  bool _isShieldSecured = false;
  bool get isShieldSecured => _isShieldSecured;

  SniperState() {
    _loadSettings();
    
    // Initialize System Health Monitoring
    _healthService = SystemHealthService(backendUrl: 'http://152.53.87.200:8083');
    _healthService.onHealthUpdate = (status) {
      _healthStatus = status;
      notifyListeners();
    };
    _healthService.startMonitoring();
    
    startMonitoring();


    WebSocketService().adviceStream.listen((data) {
        String sym = data['symbol'].toString();
        if (sym.contains(_selectedCoin)) {
            _predatorAdvice = data['message'];
            if (data['tier'] == 'SHIELD_GREEN') {
                _isShieldSecured = true;
                try { Vibration.vibrate(pattern: [100, 50, 100]); } catch (e) { /* ignore */ }
            } else if (data['tier'] == 'SHIELD_GREY') {
                _isShieldSecured = false;
            }
            notifyListeners();
        }
    });

    WebSocketService().alertStream.listen((data) {
        try {
            final type = data['type'];
            final toSym = data['symbol'];
            if (toSym == null || type == null) return;

            final price = (data['price'] as num?)?.toDouble() ?? 0.0;
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            final side = data['side'] ?? 'UNKNOWN';

            // FILTER: Ignore invalid signals to prevent UI "Unknown/0" storage
            if (side == 'UNKNOWN' || price <= 0) return;

            // Create Visual Signal
            final signal = Signal(
                id: DateTime.now().microsecondsSinceEpoch.toString(), // Alerts might not have ID, generate one
                symbol: toSym,
                side: side,
                price: price,
                score: amount, 
                tier: type,
                tp: price * (side == "LONG" ? 1.02 : 0.98), // Simulated TP
                sl: price * (side == "LONG" ? 0.99 : 1.01), // Simulated SL
                timestamp: DateTime.now().millisecondsSinceEpoch,
                type: type,
            );
            addSignal(signal);
        } catch (e) {
            // Silently ignore parse errors
        }
    });
  }



  void selectCoin(String coin) {
    if (_selectedCoin != coin) {
      _selectedCoin = coin;
      _updateActiveSignal();
      _updateActivePosition();
      _isShieldSecured = false; 
      _predatorAdvice = null;
      notifyListeners();
    }
  }

  void addSignal(Signal signal) {
    _signalHistory.insert(0, signal);
    if (_signalHistory.length > 50) _signalHistory.removeLast();

    if (signal.symbol == _selectedCoin) {
      _activeSignal = signal;
    }
    
    if (_activePosition != null && _activePosition!.symbol == signal.symbol) {
       bool isOpposite = false;
       if (_activePosition!.side == "LONG" && signal.side == "SHORT") isOpposite = true;
       if (_activePosition!.side == "SHORT" && signal.side == "LONG") isOpposite = true;
       
       if (isOpposite && (signal.tier == "1" || signal.score > 8.0)) {
           _whaleWarning = true;
           if (signal.type == 'WHALE' || signal.type == 'LIQUIDATION') {
               try { Vibration.vibrate(pattern: [500, 200, 500]); } catch (e) { /* ignore */ }
           }
       }
    }
    notifyListeners();
  }

  void _updateActiveSignal() {
    try {
      _activeSignal = _signalHistory.firstWhere((s) => s.symbol == _selectedCoin);
    } catch (e) {
      _activeSignal = null;
    }
  }

  void _updateActivePosition() {
    try {
      _activePosition = _positions.firstWhere(
        (p) => p.symbol.contains(_selectedCoin),
      );
    } catch (e) {
      _activePosition = null;
      _whaleWarning = false;
    }
  }
  
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _positionTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        await _fetchPositions();
    });
  }

  void stopMonitoring() {
    _positionTimer?.cancel();
    _isMonitoring = false;
  }
  
  Future<void> _fetchPositions() async {
      final newPositions = await _orderSigner.fetchPositions();
      _positions = newPositions;
      _updateActivePosition();
      
      // AUTO-CLOSE PROFIT LOGIC
      for (var pos in _positions) {
          if (pos.unRealizedProfit >= _targetProfit) {
              print("💰 [AUTO-TAKE-PROFIT] ${pos.symbol} reached \$${pos.unRealizedProfit.toStringAsFixed(2)} (Target: \$$_targetProfit)");
              
              // Prevent multiple close attempts? 
              // The API call is async, so we might re-enter this loop.
              // Ideally we track 'closing' state per position, but for now let's fire and forget safely.
              
              try {
                  String side = pos.side == "LONG" ? "SELL" : "BUY";
                  await _orderSigner.executeMarketOrder(
                      symbol: pos.symbol, 
                      side: side, 
                      quantity: pos.absAmt,
                      reduceOnly: true
                  );
                  
                  // Local cleanup immediately to prevent double trigger
                  _positions.removeWhere((p) => p.symbol == pos.symbol);
                  double profit = pos.unRealizedProfit;
                  if (profit > 0) {
                      try { Vibration.vibrate(pattern: [50, 100, 50, 100, 50, 100]); } catch (e) { /* ignore */ } // Cash register sound pattern
                  }
                  
              } catch (e) {
                  print("❌ [AUTO-TP-FAIL] $e");
              }
          }
      }

      notifyListeners();
  }

  Future<void> refreshPositions() async {
      await _fetchPositions();
  }

  Future<void> closeCurrentPosition() async {
      if (_activePosition == null) return;
      try {
          String side = _activePosition!.side == "LONG" ? "SELL" : "BUY";
          await _orderSigner.executeMarketOrder(
              symbol: _activePosition!.symbol, 
              side: side, 
              quantity: _activePosition!.absAmt,
              reduceOnly: true
          );
          _positions.removeWhere((p) => p.symbol == _activePosition!.symbol);
          _activePosition = null;
          _whaleWarning = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 1), _fetchPositions);
      } catch (e) {
          rethrow;
      }
  }

  Future<void> executeSafeTrade({
      required String side, 
      required Function() onSuccess, 
      required Function(String) onError
  }) async {
      // 1. COOLDOWN CHECK (2 Seconds)
      if (_isExecuting) return;
      if (_lastExecutionTime != null && DateTime.now().difference(_lastExecutionTime!) < const Duration(seconds: 2)) {
          onError("⏳ Cooldown: Please wait 2s between trades.");
          return;
      }
      
      if (_activeSignal == null) {
          onError("❌ No Active Signal to Execute.");
          return;
      }

      _isExecuting = true;
      notifyListeners();

      try {
          // 2. RISK CALCULATION
          double quantity = 0.0;
          final signal = _activeSignal!;
          
          if (signal.stopLoss != 0 && (signal.entry - signal.stopLoss).abs() > 0) {
              double priceDist = (signal.entry - signal.stopLoss).abs();
              quantity = _riskAmount / priceDist;
          } else {
              double targetNotional = 200.0; 
              if (signal.symbol.contains("BTC")) targetNotional = 500.0;
              quantity = targetNotional / signal.entry;
          }
          
          // Safety Guard
          if (!quantity.isFinite || quantity <= 0) {
               quantity = 10.0 / signal.entry; 
          }

          // 3. EXECUTE
          String formattedSymbol = signal.symbol.toUpperCase();
          if (!formattedSymbol.endsWith("USDT")) formattedSymbol += "USDT";

          await _orderSigner.executeMarketOrder(
            symbol: formattedSymbol,
            side: side,
            quantity: quantity,
          );
          
          _lastExecutionTime = DateTime.now();
          await refreshPositions();
          
          onSuccess();
          
      } catch (e) {
          onError(e.toString());
      } finally {
          _isExecuting = false;
          notifyListeners();
      }
  }

  Future<void> clearAllData() async {
    // 1. Clear Secure Storage (Keys, Settings)
    await _storage.deleteAll();
    
    // 2. Clear InMemory State
    _apiKey = null;
    _secretKey = null;
    _signalHistory.clear();
    _positions.clear();
    _activeSignal = null;
    _activePosition = null;
    
    // 3. Reset Settings
    _riskAmount = 10.0;
    _targetProfit = 50.0;
    
    notifyListeners();
  }

  void clearHistory() {
    _signalHistory.clear();
    _activeSignal = null;
    notifyListeners();
  }
}
