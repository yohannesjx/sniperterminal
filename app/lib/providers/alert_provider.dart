import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/alert.dart';

// WebSocket URL provider
final webSocketUrlProvider = Provider<String>((ref) {
  return 'ws://localhost:8080/ws';
});

// WebSocket channel provider
final webSocketChannelProvider = Provider<WebSocketChannel>((ref) {
  final url = ref.watch(webSocketUrlProvider);
  print('🔌 Connecting to WebSocket at $url');
  return WebSocketChannel.connect(Uri.parse(url));
});

// Alert stream provider
final alertStreamProvider = StreamProvider<Alert>((ref) {
  final channel = ref.watch(webSocketChannelProvider);
  print('🌊 Listening to WebSocket stream');
  
  return channel.stream.map((data) {
    // print('📦 Received raw data: ${data.toString().substring(0, 50)}...'); // Verbose logging
    final json = jsonDecode(data as String) as Map<String, dynamic>;
    return Alert.fromJson(json);
  });
});

// Selected coin provider
final selectedCoinProvider = StateProvider<String>((ref) => 'BTC');

// Filtered alert stream provider
final filteredAlertStreamProvider = StreamProvider<Alert>((ref) {
  final selectedCoin = ref.watch(selectedCoinProvider);
  final channel = ref.watch(webSocketChannelProvider);
  
  return channel.stream.map((data) {
    try {
      // print('📦 Raw: ${data.toString().substring(0, 30)}...'); // Debug raw
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      return Alert.fromJson(json);
    } catch (e) {
      print('❌ Error parsing alert: $e');
      throw e;
    }
  }).where((alert) {
    // print('🔍 Filter: ${alert.symbol}'); // Debug filter
    return selectedCoin == 'ALL' || alert.symbol == selectedCoin;
  });
});

// Price Cache Provider: Stores the last known price for each symbol
final priceCacheProvider = StateProvider<Map<String, double>>((ref) => {});

// Current Price Provider (for the header)
final currentPriceProvider = StateProvider<double>((ref) => 0.0);

// Latest Symbol Provider (for the header to show which coin updated)
final latestSymbolProvider = StateProvider<String>((ref) => '');

// Current Confidence Score Provider (for trend flip detection in passive monitoring)
final currentConfidenceScoreProvider = StateProvider<int>((ref) => 50);


// Recent alerts provider (for radar blips) - Multi-coin state isolation
final recentAlertsProvider = StateNotifierProvider<RecentAlertsNotifier, Map<String, List<Alert>>>((ref) {
  return RecentAlertsNotifier();
});

class RecentAlertsNotifier extends StateNotifier<Map<String, List<Alert>>> {
  RecentAlertsNotifier() : super({
    'BTC': [],
    'ETH': [],
    'SOL': [],
    'ALL': [], // For "ALL" view, stores all alerts
  });
  
  Timer? _cleanupTimer;
  
  void addAlert(Alert alert) {
    // 1. Get the symbol (ensure it's uppercase)
    String symbol = alert.symbol.toUpperCase();
    
    // 2. Initialize bucket if missing
    if (!state.containsKey(symbol)) {
      state = {...state, symbol: []};
    }
    
    // 3. Add to specific coin bucket
    final coinAlerts = [alert, ...state[symbol]!];
    
    // 4. Add to ALL bucket
    final allAlerts = [alert, ...state['ALL']!];
    
    // 5. Update state with both buckets
    state = {
      ...state,
      symbol: coinAlerts.length > 50 ? coinAlerts.sublist(0, 50) : coinAlerts,
      'ALL': allAlerts.length > 50 ? allAlerts.sublist(0, 50) : allAlerts,
    };
    
    // Start cleanup timer if not already running
    _cleanupTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      _cleanup();
    });
  }
  
  // Get alerts for a specific coin
  List<Alert> getAlertsFor(String symbol) {
    return state[symbol.toUpperCase()] ?? [];
  }
  
  // Clear alerts for a specific coin
  void clearCoin(String symbol) {
    state = {
      ...state,
      symbol.toUpperCase(): [],
    };
  }
  
  void _cleanup() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanedState = <String, List<Alert>>{};
    
    // Clean each coin's alerts
    state.forEach((coin, alerts) {
      cleanedState[coin] = alerts.where((alert) {
        return now - alert.data.timestamp < 60000; // 60 seconds
      }).toList();
    });
    
    state = cleanedState;
  }
  
  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }
}

// Ticker tape provider (Level 1 trades)
final tickerTapeProvider = StateNotifierProvider<TickerTapeNotifier, List<Alert>>((ref) {
  return TickerTapeNotifier();
});

class TickerTapeNotifier extends StateNotifier<List<Alert>> {
  TickerTapeNotifier() : super([]);
  
  void addTrade(Alert alert) {
    // Only add Level 1 trades
    if (alert.level == 1) {
      state = [alert, ...state];
      
      // Keep only last 100 trades
      if (state.length > 100) {
        state = state.sublist(0, 100);
      }
    }
  }
}

// Sentiment Provider (Market Buy/Sell Pressure)
final sentimentProvider = StateProvider<Map<String, double>>((ref) => {
  'buyVol': 0.0,
  'sellVol': 0.0,
  'ratio': 0.5, // Default neutral
});

// Pain Threshold Provider (User-configurable minimum alert value)
final painThresholdProvider = StateProvider<double>((ref) => 10000.0); // Default $10k (lowered from $100k)

