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

  // Max Hold Time Default (120 min)
  int _maxHoldTime = 120;
  int get maxHoldTime => _maxHoldTime;

  Future<void> setMaxHoldTime(int val) async {
    _maxHoldTime = val;
    await _storage.write(key: 'max_hold_time', value: val.toString());
    notifyListeners();
  }

  // Risk Management
  double _riskAmount = 10.0; // Default $10 risk per trade
  double get riskAmount => _riskAmount;
  
  // Margin Range Safety Lane ($50 - $60)
  double _minMargin = 50.0;
  double _maxMargin = 60.0; // Default 50-60 USDT
  
  double get minMargin => _minMargin;
  double get maxMargin => _maxMargin;
  RangeValues get marginRange => RangeValues(_minMargin, _maxMargin);

  Future<void> setRiskAmount(double val) async {
    _riskAmount = val;
    await _storage.write(key: 'risk_amount', value: val.toString());
    notifyListeners();
  }

  Future<void> setMarginRange(RangeValues range) async {
    _minMargin = range.start;
    _maxMargin = range.end;
    await _storage.write(key: 'min_margin', value: _minMargin.toString());
    await _storage.write(key: 'max_margin', value: _maxMargin.toString());
    notifyListeners();
  }

  // Backwards compat for old Max Margin calls 
  Future<void> setMaxMargin(double val) async {
      // If used, assume it sets Max, keep Min same? Or ignore.
      // Deprecated, but for compilation safety if Settings used it.
      // We updated Settings to use setMarginRange.
      _maxMargin = val;
      await _storage.write(key: 'max_margin', value: val.toString());
      notifyListeners();
  }

  // Aggressive Mode (Tier 2 Signals)
  bool _isAggressiveMode = false;
  bool get isAggressiveMode => _isAggressiveMode;

  Future<void> setAggressiveMode(bool val) async {
    _isAggressiveMode = val;
    await _storage.write(key: 'aggressive_mode', value: val.toString());
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    String? risk = await _storage.read(key: 'risk_amount');
    if (risk != null) _riskAmount = double.tryParse(risk) ?? 10.0;
    
    String? minM = await _storage.read(key: 'min_margin');
    if (minM != null) _minMargin = double.tryParse(minM) ?? 50.0;
    
    String? maxM = await _storage.read(key: 'max_margin');
    if (maxM != null) _maxMargin = double.tryParse(maxM) ?? 60.0;
    
    String? agg = await _storage.read(key: 'aggressive_mode');
    if (agg != null) _isAggressiveMode = agg == 'true';

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
    
    // Load Precision Data for OrderSigner
    _orderSigner.fetchExchangeInfo().then((_) {
        print("✅ [SNIPER_STATE] Exchange Info Loaded");
    });

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
            var type = data['type'];
            final toSym = data['symbol'];
            var tier = data['tier'];

            // SUPPORT BOTH ALERT AND SIGNAL FORMATS
            if (toSym == null) return;
            if (type == null && tier == null) return;

            // If it's a Signal (has tier but no type), force type = SIGNAL
            if (type == null && tier != null) {
                type = 'SIGNAL';
            }
            // If it's an Alert (has type but no tier), use type as tier
            if (tier == null && type != null) {
                tier = type;
            }

            final price = (data['price'] as num?)?.toDouble() ?? 0.0;
            final amount = (data['amount'] as num?)?.toDouble() ?? 
                          (data['score'] as num?)?.toDouble() ?? 0.0; // Handle score
            final side = data['side'] ?? 'UNKNOWN';

            // FILTER: Ignore invalid signals to prevent UI "Unknown/0" storage
            if (side == 'UNKNOWN' || price <= 0) return;

            // Create Visual Signal
            final signal = Signal(
                id: data['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
                symbol: toSym,
                side: side,
                price: price,
                score: amount, 
                tier: tier.toString(),
                tp: (data['tp'] as num?)?.toDouble() ?? price * (side == "LONG" ? 1.02 : 0.98),
                sl: (data['sl'] as num?)?.toDouble() ?? price * (side == "LONG" ? 0.99 : 1.01),
                timestamp: DateTime.now().millisecondsSinceEpoch,
                type: type,
            );
            addSignal(signal);
        } catch (e) {
            // Silently ignore parse errors
        }
    });
  }

  // Available Coins for Swipe Navigation
  final List<String> _availableCoins = const [
    'BTC', 'ETH', 'BNB', 'SOL', 'XRP', 
    'SUI', 'AVAX', 'ADA', 'DOGE', 'LINK',
    'HYPE', 'FET', 'TAO', 'ARB', 'OP',
    'PEPE', 'WIF', 'SHIB', 'TRX', 'LTC',
    'NEAR', 'INJ', 'APT', 'RENDER', 'SEI'
  ];
  List<String> get availableCoins => _availableCoins;

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

  void selectNextCoin() {
    int index = _availableCoins.indexOf(_selectedCoin);
    if (index == -1) index = 0;
    
    int nextIndex = (index + 1) % _availableCoins.length;
    selectCoin(_availableCoins[nextIndex]);
  }

  void selectPreviousCoin() {
    int index = _availableCoins.indexOf(_selectedCoin);
    if (index == -1) index = 0;
    
    int prevIndex = (index - 1);
    if (prevIndex < 0) prevIndex = _availableCoins.length - 1;
    
    selectCoin(_availableCoins[prevIndex]);
  }

  void addSignal(Signal signal) {
    // FILTER: Only allow Tier 1 unless Aggressive Mode is ON
    bool isTier1 = signal.tier.contains("Tier 1") || signal.tier == "1";
    if (!isTier1 && !_isAggressiveMode) {
        return; 
    }

    _signalHistory.insert(0, signal);
    if (_signalHistory.length > 50) _signalHistory.removeLast();

    if (signal.symbol == _selectedCoin) {
      _activeSignal = signal;
    }
    
    if (_activePosition != null && _activePosition!.symbol == signal.symbol) {
       bool isOpposite = false;
       if (_activePosition!.side == "LONG" && signal.side == "SHORT") isOpposite = true;
       if (_activePosition!.side == "SHORT" && signal.side == "LONG") isOpposite = true;
       
       if (isOpposite && (signal.tier.contains("Tier 1") || signal.tier == "1" || signal.score > 8.0)) {
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
  
  // --- QUEUE & SNIPE LOGIC ---

  // 1. Sorted Signal Queue (Priority: Score * Ratio)
  List<Signal> get sortedSignals {
      final valid = _signalHistory.where((s) => 
          DateTime.fromMillisecondsSinceEpoch(s.timestamp).difference(DateTime.now()).inMinutes.abs() < 60
      ).toList();
      
      valid.sort((a, b) {
          double scoreA = a.score * (double.tryParse(a.tier) ?? 1.0); // Use Ratio if available, else 1
          double scoreB = b.score * (double.tryParse(b.tier) ?? 1.0);
          return scoreB.compareTo(scoreA); // Descending
      });
      return valid;
  }

  // 2. Cumulative Fleet Profit
  double get cumulativeProfit {
      return _positions.fold(0.0, (sum, p) => sum + p.unRealizedProfit);
  }

  // 3. Close All In Profit
  Future<void> closeAllInProfit() async {
      final profitable = _positions.where((p) => p.unRealizedProfit > 1.0).toList(); // Net > $1
      
      for (var p in profitable) {
          try {
             String side = p.positionAmt > 0 ? "SELL" : "BUY";
             await _orderSigner.executeMarketOrder(
                 symbol: p.symbol,
                 side: side,
                 quantity: p.absAmt,
                 reduceOnly: true
             );
          } catch (e) {
              print("Failed to close ${p.symbol}: $e");
          }
      }
      notifyListeners();
      try { Vibration.vibrate(pattern: [50, 50, 200]); } catch (_) {}
  }

  // 4. One-Tap Snipe Execution
  Future<void> executeSnipe(Signal signal) async {
       // Auto-calculate for $50 Margin @ 10x (Total $500 Notional)
       double notional = 500.0;
       double quantity = notional / signal.price;
       
       String side = signal.side == "LONG" ? "BUY" : "SELL";
       
       try {
           await _orderSigner.executeMarketOrder(
               symbol: signal.symbol,
               side: side,
               quantity: quantity
           );
           
           // Auto Set TP/SL?
           // For now, raw snipe.
           
           notifyListeners();
           try { Vibration.vibrate(duration: 100); } catch (_) {}
       } catch (e) {
           rethrow;
       }
  }

  // --- EXISTING METHODS BELOW ---
  
  Future<void> _fetchPositions() async {
      final newPositions = await _orderSigner.fetchPositions();
      _positions = newPositions;
      _updateActivePosition();
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
          final signal = _activeSignal!;
          
          // --- QUANT SAFETY CHECK START ---
          
          // A. SLIPPAGE BUFFER (0.01%)
          // Assume entry is slightly worse than signal price
          double realEntry = signal.entry;
          if (side == "LONG") {
              realEntry = signal.entry * 1.0001; 
          } else {
              realEntry = signal.entry * 0.9999;
          }

          // B. LEVERAGE GUARD (Max 2% Equity Risk)
          double equity = await _orderSigner.fetchAccountBalance();
          if (equity == 0) equity = 1000.0; // Fallback if API fails (or testnet 0) to avoid divide by zero? Better to warn.
          
          double maxRiskDollar = equity * 0.02; // 2% of Account
          double priceRiskPerUnit = (realEntry - signal.sl).abs();
          
          if (priceRiskPerUnit == 0) priceRiskPerUnit = realEntry * 0.01; // Prevent div/0 (1% fallback width)
          
          double maxQtyAllowed = maxRiskDollar / priceRiskPerUnit;

          // C. MARGIN RANGE CLAMPING ($50 - $60 Safety Lane)
          // 1. Calculate raw quantity from risk ($10 etc)
          double rawQty = 0.0;
          if (signal.stopLoss != 0 && priceRiskPerUnit > 0) {
              rawQty = _riskAmount / priceRiskPerUnit;
          } else {
              // Notional Fallback if SL missing
              double targetNotional = 200.0; 
              if (signal.symbol.contains("BTC")) targetNotional = 500.0;
              rawQty = targetNotional / realEntry;
          }

          // 2. Clamp projected Margin logic (Approximation 20x for Safety Lane)
          // We assume user thinks in terms of "Cost" or "Initial Margin".
          // Projected Margin = (RawQty * Entry) / 20.0;
          double projectedMargin = (rawQty * realEntry) / 20.0;
          
          if (projectedMargin < _minMargin) projectedMargin = _minMargin;
          if (projectedMargin > _maxMargin) projectedMargin = _maxMargin;
          
          // 3. Recalculate Qty from Clamped Margin
          double quantity = (projectedMargin * 20.0) / realEntry;

          // D. NOTIONAL GUARD (Min $20)
          double finalNotional = quantity * realEntry;
          if (finalNotional < 20.0) {
               print("⚠️ [NOTIONAL GUARD] Boosting trade to \$20 Notional.");
               quantity = 20.0 / realEntry;
          }
          
          // E. LEVERAGE GUARD CHECK
          if (quantity > maxQtyAllowed) {
               print("🛡️ [LEVERAGE GUARD] Cap hit. Reducing to max allowed.");
               quantity = maxQtyAllowed;
          }

          // F. PROFIT CHECK ($1 Net - Allow Scalps)
          double grossProfit = (signal.tp - realEntry).abs() * quantity;
          double estimatedFees = (realEntry * quantity) * 0.001; 
          if (grossProfit - estimatedFees < 1.0) {
              throw "🛑 TRADE REJECTED: Profit < \$1 (Fees too high).";
          }

          // --- QUANT SAFETY CHECK END ---

          // 4. EXECUTE
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
    _minMargin = 50.0;
    _maxMargin = 60.0;
    _isAggressiveMode = false;
    
    notifyListeners();
  }

  Future<void> setProfitTarget(double targetPrice) async {
      if (_activePosition == null) {
          throw "No active position to set target for.";
      }
      
      try {
          String side = _activePosition!.side == "LONG" ? "SELL" : "BUY";
          
          await _orderSigner.executeLimitOrder(
              symbol: _activePosition!.symbol,
              side: side,
              quantity: _activePosition!.absAmt,
              price: targetPrice,
              reduceOnly: true
          );
          
          try { Vibration.vibrate(pattern: [50, 50, 50]); } catch (e) { /* ignore */ }
          
      } catch (e) {
          rethrow;
      }
  }

  // Quick Target Logic ($2, $5, $10)
  Future<void> setQuickTarget(double dollarProfit) async {
    if (_activePosition == null) return;
    
    // 1. INSTANT HARVEST CHECK
    // If we are already in profit >= target, CLOSE NOW.
    if (_activePosition!.unRealizedProfit >= dollarProfit) {
         print("⚡ [INSTANT HARVEST] PnL (${_activePosition!.unRealizedProfit}) >= Target ($dollarProfit). CLOSING NOW.");
         try {
             String side = _activePosition!.positionAmt > 0 ? "SELL" : "BUY";
             await _orderSigner.executeMarketOrder(
                 symbol: _activePosition!.symbol,
                 side: side,
                 quantity: _activePosition!.absAmt,
                 reduceOnly: true
             );
             // Vibration handled by order signer success usually, but we can double up for feel
             try { Vibration.vibrate(pattern: [50, 50, 50, 100]); } catch (_) {}
             return;
         } catch (e) {
             print("❌ Instant Harvest Failed: $e");
             // Fallthrough to set limit? No, better to alert.
             rethrow;
         }
    }

    // 2. SET LIMIT ORDER (Standard Behavior)
    double entry = _activePosition!.entryPrice;
    double size = _activePosition!.absAmt;
    if (size == 0) return;

    // Profit = (Exit - Entry) * Size
    // Exit = (Profit / Size) + Entry (for Long)
    // Exit = Entry - (Profit / Size) (for Short)

    double priceDelta = dollarProfit / size;
    double targetPrice = 0.0;

    if (_activePosition!.side == "LONG") {
      targetPrice = entry + priceDelta;
    } else {
      targetPrice = entry - priceDelta;
    }

    await setProfitTarget(targetPrice);
  }

  void clearHistory() {
    _signalHistory.clear();
    _activeSignal = null;
    notifyListeners();
  }

}
