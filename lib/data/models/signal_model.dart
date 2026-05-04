import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/trading/fx_pair_utils.dart';

enum SignalType { buy, sell }

/// Collezione Firestore del documento (`signals` vs `test_signals`).
enum SignalFirestoreCollection {
  live,
  test,
}

class SignalModel {
  final String id;
  final String userId;
  final String pair;
  final SignalType type;
  final double score;
  final DateTime timestamp;
  final double entryPrice;
  final double stopLoss;
  final double takeProfit;
  final Map<String, dynamic> indicatorsSnapshot;
  final bool isProcessed;
  final bool isTest;
  final DateTime createdAt;
  final double? realizedPips; // pips realizzati (opzionale)
  final double? exitPrice; // prezzo di uscita (opzionale)
  final DateTime? exitTime; // data/ora di uscita (opzionale)
  final double? minLotPerTrade;
  final double? profitQuoteCurrency; // P&L nella valuta di quotazione
  final String? quoteCurrency; // es. USD, JPY, EUR
  final double? realizedPnlEuro; // P&L stimato in EUR (report)
  final String? pnlConversionNote;
  /// Motivo chiusura simulazione (es. SL, TP, no_exit) — campo Firestore `exit_reason`.
  final String? exitReason;
  final double? spreadEntryPips;
  final double? spreadExitPips;
  final double? spreadRoundTripPips;
  final double? spreadPaidEuro;
  final String? spreadNote;
  /// Variazioni effettive dello SL (break-even / trailing) in simulazione 1m o live.
  final int stopLossAdjustmentCount;

  /// Copia dei campi letti da Firestore (per dettaglio completo in UI).
  final Map<String, dynamic> rawFirestore;

  /// Origine documento (per consentire modifiche solo sui segnali live).
  final SignalFirestoreCollection documentSource;

  /// Conferma manuale dell’esecuzione reale dell’ordine sul broker.
  final bool executionConfirmed;

  SignalModel({
    required this.id,
    required this.userId,
    required this.pair,
    required this.type,
    required this.score,
    required this.timestamp,
    required this.entryPrice,
    required this.stopLoss,
    required this.takeProfit,
    required this.indicatorsSnapshot,
    required this.isProcessed,
    required this.isTest,
    required this.createdAt,
    this.realizedPips,
    this.exitPrice,
    this.exitTime,
    this.minLotPerTrade,
    this.profitQuoteCurrency,
    this.quoteCurrency,
    this.realizedPnlEuro,
    this.pnlConversionNote,
    this.exitReason,
    this.spreadEntryPips,
    this.spreadExitPips,
    this.spreadRoundTripPips,
    this.spreadPaidEuro,
    this.spreadNote,
    this.stopLossAdjustmentCount = 0,
    required this.rawFirestore,
    this.documentSource = SignalFirestoreCollection.live,
    this.executionConfirmed = false,
  });

  factory SignalModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SignalModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      pair: data['pair'] ?? '',
      type: data['type'] == 'buy' ? SignalType.buy : SignalType.sell,
      score: (data['score'] as num?)?.toDouble() ?? 0.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      entryPrice: (data['entryPrice'] as num?)?.toDouble() ?? 0.0,
      stopLoss: (data['stopLoss'] as num?)?.toDouble() ?? 0.0,
      takeProfit: (data['takeProfit'] as num?)?.toDouble() ?? 0.0,
      indicatorsSnapshot:
          (data['indicatorsSnapshot'] as Map<String, dynamic>?) ?? {},
      isProcessed: data['isProcessed'] ?? false,
      isTest: data['isTest'] ?? false,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      realizedPips: _readNum(data, const ['realized_pips', 'realizedPips']),
      exitPrice: _readNum(data, const ['exit_price', 'exitPrice']),
      exitTime: (data['exit_time'] as Timestamp?)?.toDate() ??
          (data['exitTime'] as Timestamp?)?.toDate(),
      minLotPerTrade: _readNum(data, const ['minLotPerTrade']),
      profitQuoteCurrency:
          _readNum(data, const ['profit_quote_currency', 'profitQuoteCurrency']),
      quoteCurrency:
          (data['quote_currency'] ?? data['quoteCurrency']) as String?,
      realizedPnlEuro:
          _readNum(data, const ['realized_pnl_eur', 'realizedPnlEuro']),
      pnlConversionNote: data['pnl_conversion_note'] as String?,
      exitReason: (data['exit_reason'] ?? data['exitReason'])?.toString(),
      spreadEntryPips: _readNum(data, const ['spread_entry_pips', 'spreadEntryPips']),
      spreadExitPips: _readNum(data, const ['spread_exit_pips', 'spreadExitPips']),
      spreadRoundTripPips:
          _readNum(data, const ['spread_round_trip_pips', 'spreadRoundTripPips']),
      spreadPaidEuro: _readNum(data, const ['spread_paid_eur', 'spreadPaidEuro']),
      spreadNote: data['spread_note'] as String? ?? data['spreadNote'] as String?,
      stopLossAdjustmentCount: _readInt(data, const [
        'stopLossAdjustmentCount',
        'stop_loss_adjustment_count',
      ]),
      rawFirestore: Map<String, dynamic>.from(data),
      documentSource: doc.reference.parent.id == 'test_signals'
          ? SignalFirestoreCollection.test
          : SignalFirestoreCollection.live,
      executionConfirmed: data['executionConfirmed'] == true ||
          data['execution_confirmed'] == true,
    );
  }

  static double? _readNum(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
    }
    return null;
  }

  static int _readInt(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) {
        final p = int.tryParse(v.trim());
        if (p != null) return p;
      }
    }
    return 0;
  }

  /// Segnale chiuso in simulazione / con uscita registrata.
  bool get isClosed => exitPrice != null || exitTime != null;

  /// Pips mostrati: preferisce il valore salvato dal backtest, altrimenti stima da entry/exit.
  /// Se manca `realizedPips` ma c'è `profitQuoteCurrency` e il lotto, ricava i pips dal P&L
  /// (coerente con il backend: P&L = lot × 100k × pips × pip_size).
  double? get effectivePips {
    if (realizedPips != null) return realizedPips;
    final lot = minLotPerTrade;
    final pq = profitQuoteCurrency;
    if (lot != null && lot > 0 && pq != null && pq != 0) {
      final pipSz = pipSizeForPair(pair);
      const contract = 100000.0;
      final implied = pq / (lot * contract * pipSz);
      if (implied.isFinite) return implied;
    }
    if (exitPrice == null) return null;
    final mult = pipMultiplierForPair(pair);
    if (type == SignalType.buy) {
      return (exitPrice! - entryPrice) * mult;
    }
    return (entryPrice - exitPrice!) * mult;
  }

  /// Durata tra apertura (`timestamp`) e chiusura (`exitTime`), se entrambe presenti.
  Duration? get openDuration {
    if (exitTime == null) return null;
    return exitTime!.difference(timestamp);
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'pair': pair,
      'type': type == SignalType.buy ? 'buy' : 'sell',
      'score': score,
      'timestamp': Timestamp.fromDate(timestamp),
      'entryPrice': entryPrice,
      'stopLoss': stopLoss,
      'takeProfit': takeProfit,
      'indicatorsSnapshot': indicatorsSnapshot,
      'isProcessed': isProcessed,
      'isTest': isTest,
      'createdAt': Timestamp.fromDate(createdAt),
      if (realizedPips != null) 'realizedPips': realizedPips,
      if (exitPrice != null) 'exitPrice': exitPrice,
      if (exitTime != null) 'exitTime': Timestamp.fromDate(exitTime!),
      if (minLotPerTrade != null) 'minLotPerTrade': minLotPerTrade,
      if (profitQuoteCurrency != null) 'profit_quote_currency': profitQuoteCurrency,
      if (quoteCurrency != null) 'quote_currency': quoteCurrency,
      if (realizedPnlEuro != null) 'realized_pnl_eur': realizedPnlEuro,
      if (pnlConversionNote != null) 'pnl_conversion_note': pnlConversionNote,
      if (exitReason != null) 'exit_reason': exitReason,
      if (spreadEntryPips != null) 'spread_entry_pips': spreadEntryPips,
      if (spreadExitPips != null) 'spread_exit_pips': spreadExitPips,
      if (spreadRoundTripPips != null) 'spread_round_trip_pips': spreadRoundTripPips,
      if (spreadPaidEuro != null) 'spread_paid_eur': spreadPaidEuro,
      if (spreadNote != null) 'spread_note': spreadNote,
      'stopLossAdjustmentCount': stopLossAdjustmentCount,
      'executionConfirmed': executionConfirmed,
    };
  }
}
