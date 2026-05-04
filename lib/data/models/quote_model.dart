import '../../core/trading/fx_pair_utils.dart';

class QuoteModel {
  final String epic;
  final double bid;
  final double ofr;
  final double price;
  final int timestamp;
  final String marketStatus;
  final DateTime updateTime;
  /// Sessione / range giornaliero dallo snapshot Capital (`GET /markets/{epic}`).
  final double? high;
  final double? low;
  /// Variazione percentuale dallo snapshot (es. rispetto alla chiusura precedente).
  final double? percentageChange;
  final double? netChange;
  /// Fattore decimali suggerito dall'API (`decimalPlacesFactor`); opzionale.
  final int? decimalPlacesFactor;

  QuoteModel({
    required this.epic,
    required this.bid,
    required this.ofr,
    required this.price,
    required this.timestamp,
    required this.marketStatus,
    required this.updateTime,
    this.high,
    this.low,
    this.percentageChange,
    this.netChange,
    this.decimalPlacesFactor,
  });

  /// Decimali prezzo per la formattazione (JPY vs altre; preferisce `decimalPlacesFactor` se coerente).
  int get priceFractionDigits {
    final e = normalizedPairEpic(epic);
    final jpy = e.length == 6 && e.substring(3, 6) == 'JPY';
    final f = decimalPlacesFactor;
    if (f != null && f >= 1) {
      if (jpy) return f.clamp(2, 4);
      return f.clamp(4, 6);
    }
    return jpy ? 3 : 5;
  }

  factory QuoteModel.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'] as Map<String, dynamic>;
    final updateTimeStr = snapshot['updateTime'] as String;
    final updateTime = DateTime.parse(updateTimeStr);
    final epic = (json['instrument'] as Map<String, dynamic>)['epic'] as String;

    double? readOptNum(String key) {
      final v = snapshot[key];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return null;
    }

    return QuoteModel(
      epic: epic,
      bid: (snapshot['bid'] as num).toDouble(),
      ofr: (snapshot['offer'] as num).toDouble(),
      price: ((snapshot['bid'] as num) + (snapshot['offer'] as num)) / 2,
      timestamp: updateTime.millisecondsSinceEpoch,
      marketStatus: snapshot['marketStatus'] as String,
      updateTime: updateTime,
      high: readOptNum('high'),
      low: readOptNum('low'),
      percentageChange: readOptNum('percentageChange'),
      netChange: readOptNum('netChange'),
      decimalPlacesFactor: (snapshot['decimalPlacesFactor'] as num?)?.toInt(),
    );
  }
}
