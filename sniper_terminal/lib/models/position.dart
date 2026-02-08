class Position {
  final String symbol;
  final double entryPrice;
  final double markPrice;
  final double unRealizedProfit;
  final double positionAmt; // Negative for Short, Positive for Long
  final double leverage;
  final String marginType; // isolated or cross
  final double liquidationPrice;
  final double isolatedMargin;
  final double notional;

  Position({
    required this.symbol,
    required this.entryPrice,
    required this.markPrice,
    required this.unRealizedProfit,
    required this.positionAmt,
    required this.leverage,
    required this.marginType,
    required this.liquidationPrice,
    required this.isolatedMargin,
    required this.notional,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      symbol: json['symbol'],
      entryPrice: double.tryParse(json['entryPrice'].toString()) ?? 0.0,
      markPrice: double.tryParse(json['markPrice'].toString()) ?? 0.0,
      unRealizedProfit: double.tryParse(json['unRealizedProfit'].toString()) ?? 0.0,
      positionAmt: double.tryParse(json['positionAmt'].toString()) ?? 0.0,
      leverage: double.tryParse(json['leverage'].toString()) ?? 1.0,
      marginType: json['marginType'] ?? 'isolated',
      liquidationPrice: double.tryParse(json['liquidationPrice'].toString()) ?? 0.0,
      isolatedMargin: double.tryParse(json['isolatedMargin'].toString()) ?? 0.0,
      notional: double.tryParse(json['notional'].toString()) ?? 0.0,
    );
  }
  
  bool get isOpen => positionAmt != 0;
  String get side => positionAmt > 0 ? "LONG" : "SHORT";
  double get absAmt => positionAmt.abs();
  double get roe => (unRealizedProfit / (absAmt * entryPrice / leverage)) * 100;
}
