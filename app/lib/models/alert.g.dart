// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Alert _$AlertFromJson(Map<String, dynamic> json) => Alert(
      type: json['type'] as String,
      level: (json['level'] as num).toInt(),
      symbol: json['symbol'] as String,
      message: json['message'] as String,
      data: Trade.fromJson(json['data'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$AlertToJson(Alert instance) => <String, dynamic>{
      'type': instance.type,
      'level': instance.level,
      'symbol': instance.symbol,
      'message': instance.message,
      'data': instance.data,
    };

Trade _$TradeFromJson(Map<String, dynamic> json) => Trade(
      symbol: json['symbol'] as String,
      price: (json['price'] as num).toDouble(),
      size: (json['size'] as num).toDouble(),
      notional: (json['notional'] as num).toDouble(),
      side: json['side'] as String,
      exchange: json['exchange'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
    );

Map<String, dynamic> _$TradeToJson(Trade instance) => <String, dynamic>{
      'symbol': instance.symbol,
      'price': instance.price,
      'size': instance.size,
      'notional': instance.notional,
      'side': instance.side,
      'exchange': instance.exchange,
      'timestamp': instance.timestamp,
    };
