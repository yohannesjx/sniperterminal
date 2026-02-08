class Signal {
  final String symbol;
  final String side;
  final double price;
  final double score;
  final String tier;
  final double tp;
  final double sl;
  final int timestamp;

  final String id; // Unique ID for stable rendering

  final String type; // TRADE, ICEBERG, LIQUIDATION

  double get entry => price;
  double get stopLoss => sl;

  Signal({
    required this.id,
    required this.symbol,
    required this.side,
    required this.price,
    required this.score,
    required this.tier,
    required this.tp,
    required this.sl,
    required this.timestamp,
    this.type = 'TRADE',
  });

  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      id: json['id'] ?? json['ID'] ?? DateTime.now().microsecondsSinceEpoch.toString(), // Fallback ID
      symbol: json['symbol'],
      side: json['side'],
      price: (json['price'] as num).toDouble(),
      score: (json['score'] as num).toDouble(),
      tier: json['tier'],
      tp: (json['tp'] as num).toDouble(),
      sl: (json['sl'] as num).toDouble(),
      timestamp: json['ts'],
      type: json['type'] ?? 'TRADE',
    );
  }
}
