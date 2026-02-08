import 'package:json_annotation/json_annotation.dart';

part 'alert.g.dart';

@JsonSerializable()
class Alert {
  final String type;
  final int level;
  final String symbol;
  final String message;
  final Trade data;

  Alert({
    required this.type,
    required this.level,
    required this.symbol,
    required this.message,
    required this.data,
  });

  factory Alert.fromJson(Map<String, dynamic> json) => _$AlertFromJson(json);
  Map<String, dynamic> toJson() => _$AlertToJson(this);

  // Helper getters for robust type checking
  bool get isWhale => type.toUpperCase() == 'WHALE';
  bool get isIceberg => type.toUpperCase() == 'ICEBERG';
  bool get isSpoof => type.toUpperCase() == 'SPOOF';
  bool get isLiquidation => type.toUpperCase() == 'LIQUIDATION';
  bool get isWall => type.toUpperCase() == 'WALL';
  bool get isBreakout => type.toUpperCase() == 'BREAKOUT';
  bool get isSentiment => type.toUpperCase() == 'SENTIMENT';
  
  // Sentiment data helpers (when type == SENTIMENT)
  double get sentimentBuyVol => data.notional;
  double get sentimentSellVol => data.size;
  double get sentimentRatio => data.price;
}

@JsonSerializable()
class Trade {
  final String symbol;
  final double price;
  final double size;
  final double notional;
  final String side;
  final String exchange;
  final int timestamp;

  Trade({
    required this.symbol,
    required this.price,
    required this.size,
    required this.notional,
    required this.side,
    required this.exchange,
    required this.timestamp,
  });

  factory Trade.fromJson(Map<String, dynamic> json) => _$TradeFromJson(json);
  Map<String, dynamic> toJson() => _$TradeToJson(this);
}
