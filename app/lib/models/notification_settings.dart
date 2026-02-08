class NotificationSettings {
  final bool notifyMegaWhales;      // Only whales > $1M
  final bool notifyTrendFlips;      // Only confidence crosses 35/65
  final bool notifyManipulation;    // Only spoof clusters
  final bool muteRetailTrades;      // Silence trades < $100k
  final bool notifyInBackground;    // Send push notifications for critical alerts
  final bool subscribeToWhales;     // Receive FCM alerts for ALL_WHALES topic
  
  // Thresholds
  final Map<String, double> coinThresholds; // Per-coin thresholds
  final int bearishThreshold;       // Default: 35
  final int bullishThreshold;       // Default: 65
  final int spoofClusterSize;       // Default: 3
  final double retailTradeThreshold; // Default: $100,000

  // Default Thresholds
  static const Map<String, double> defaultThresholds = {
    'BTC': 1000000.0,  // $1M
    'ETH': 500000.0,   // $500k
    'SOL': 250000.0,   // $250k
    'BNB': 250000.0,
    'XRP': 100000.0,   // $100k
    'ADA': 100000.0,
    'DOGE': 100000.0,
    'AVAX': 100000.0,
    'TRX': 50000.0,    // $50k
    'PEPE': 10000.0,   // $10k (Meme coins have lower $ volume whales)
  };

  const NotificationSettings({
    this.notifyMegaWhales = true,
    this.notifyTrendFlips = true,
    this.notifyManipulation = true,
    this.muteRetailTrades = false,
    this.notifyInBackground = true,
    this.subscribeToWhales = true,
    this.coinThresholds = defaultThresholds,
    this.bearishThreshold = 35,
    this.bullishThreshold = 65,
    this.spoofClusterSize = 3,
    this.retailTradeThreshold = 100000.0,
  });

  NotificationSettings copyWith({
    bool? notifyMegaWhales,
    bool? notifyTrendFlips,
    bool? notifyManipulation,
    bool? muteRetailTrades,
    bool? notifyInBackground,
    bool? subscribeToWhales,
    Map<String, double>? coinThresholds,
    int? bearishThreshold,
    int? bullishThreshold,
    int? spoofClusterSize,
    double? retailTradeThreshold,
  }) {
    return NotificationSettings(
      notifyMegaWhales: notifyMegaWhales ?? this.notifyMegaWhales,
      notifyTrendFlips: notifyTrendFlips ?? this.notifyTrendFlips,
      notifyManipulation: notifyManipulation ?? this.notifyManipulation,
      muteRetailTrades: muteRetailTrades ?? this.muteRetailTrades,
      notifyInBackground: notifyInBackground ?? this.notifyInBackground,
      subscribeToWhales: subscribeToWhales ?? this.subscribeToWhales,
      coinThresholds: coinThresholds ?? this.coinThresholds,
      bearishThreshold: bearishThreshold ?? this.bearishThreshold,
      bullishThreshold: bullishThreshold ?? this.bullishThreshold,
      spoofClusterSize: spoofClusterSize ?? this.spoofClusterSize,
      retailTradeThreshold: retailTradeThreshold ?? this.retailTradeThreshold,
    );
  }

  // Helper to get threshold for a specific coin
  double getThreshold(String symbol) {
    return coinThresholds[symbol.toUpperCase()] ?? 100000.0; // Default fallback
  }

  // Check if any passive monitoring is enabled
  bool get isPassiveModeEnabled {
    return notifyMegaWhales || notifyTrendFlips || notifyManipulation || muteRetailTrades;
  }

  // Check if all notifications are disabled (fully silent)
  bool get isFullySilent {
    return !notifyMegaWhales && !notifyTrendFlips && !notifyManipulation && muteRetailTrades;
  }
}
