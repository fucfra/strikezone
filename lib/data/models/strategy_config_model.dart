import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================================
// MODELLO PRINCIPALE
// ============================================================================
class StrategyConfigModel {
  String userId;
  TimeframeConfig timeframes;
  IndicatorConfig indicators;
  FilterConfig filters;
  ExitRulesConfig exitRules;
  /// Capitale iniziale (EUR) usato nel report per curva di saldo.
  double initialCapitalEuro;
  DateTime updatedAt;

  StrategyConfigModel({
    required this.userId,
    required this.timeframes,
    required this.indicators,
    required this.filters,
    required this.exitRules,
    this.initialCapitalEuro = 10000.0,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'timeframes': timeframes.toFirestore(),
      'indicators': indicators.toFirestore(),
      'filters': filters.toFirestore(),
      'exitRules': exitRules.toFirestore(),
      'initialCapitalEuro': initialCapitalEuro,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // lib/data/models/strategy_config_model.dart
  // Aggiungi un costruttore factory safe

  factory StrategyConfigModel.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) {
      // Se il documento non esiste, restituisci una configurazione di default con userId vuoto
      // (il vero userId verrà impostato dal repository)
      return StrategyConfigModel.empty();
    }

    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      return StrategyConfigModel.empty();
    }

    return StrategyConfigModel(
      userId: data['userId'] ?? '',
      timeframes: TimeframeConfig.fromFirestore(data['timeframes'] ?? {}),
      indicators: IndicatorConfig.fromFirestore(data['indicators'] ?? {}),
      filters: FilterConfig.fromFirestore(data['filters'] ?? {}),
      exitRules: ExitRulesConfig.fromFirestore(data['exitRules'] ?? {}),
      initialCapitalEuro:
          (data['initialCapitalEuro'] as num?)?.toDouble() ?? 10000.0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Costruttore di default (vuoto, con userId da impostare successivamente)
  factory StrategyConfigModel.empty() {
    return StrategyConfigModel(
      userId: '',
      timeframes: TimeframeConfig(
        operativo: '15m',
        medio: '4h',
        lungo: '1d',
        test: '1m',
      ),
      indicators: IndicatorConfig(
        emaLong: EmaLong(
          length: 200,
          weight: 25,
          enabled: true,
          timeframe: 'operativo',
        ),
        emaShort: EmaShort(
          length: 50,
          weight: 15,
          enabled: false,
          timeframe: 'operativo',
        ),
        smaSignal: SmaSignal(
          length: 20,
          weight: 10,
          enabled: false,
          timeframe: 'operativo',
        ),
        rsi: RsiConfig(
          length: 14,
          weight: 15,
          oversold: 30,
          overbought: 70,
          enabled: true,
          timeframe: 'operativo',
        ),
        macd: MacdConfig(
          fast: 12,
          slow: 26,
          signal: 9,
          weight: 10,
          enabled: false,
          timeframe: 'operativo',
        ),
        pivot: PivotConfig(
          type: 'Standard',
          weight: 10,
          enabled: false,
          timeframe: 'operativo',
        ),
        adrScore: AdrScoreConfig(
          length: 14,
          weight: 15,
          enabled: false,
          timeframe: 'operativo',
        ),
      ),
      filters: FilterConfig(
        superTrend: SuperTrendConfig(
          period: 10,
          multiplier: 3.0,
          enabled: false,
          timeframe: 'operativo',
        ),
        bollinger: BollingerConfig(
          length: 20,
          std: 2.0,
          enabled: false,
          timeframe: 'operativo',
        ),
        maxAdrExtension: 0.85,
        minAtrLevel: 0.0005,
        tradingSession: TradingSessionConfig(
          start: '08:00',
          end: '20:00',
          enabled: false,
        ),
        maxSpreadAllowed: 3.0,
        adx: AdxConfig(
          period: 14,
          threshold: 20,
          filterDi: false,
          enabled: false,
          timeframe: 'operativo',
        ),
      ),
      exitRules: ExitRulesConfig(
        maxSimultaneousTrades: 3,
        activationScore: 55,
        slAtrMult: 2.0,
        tpAtrMult: 4.0,
        minLotPerTrade: 0.01,
        breakEven: BreakEvenConfig(
          active: false,
          triggerAtrMult: 1.0,
          lockAtrMult: 0.1,
        ),
        trailingStop: TrailingStopConfig(
          active: true,
          activationAtrMult: 1.5,
          stepAtrMult: 1.0,
        ),
      ),
      initialCapitalEuro: 10000.0,
      updatedAt: DateTime.now(),
    );
  }

  StrategyConfigModel copyWith({
    String? userId,
    TimeframeConfig? timeframes,
    IndicatorConfig? indicators,
    FilterConfig? filters,
    ExitRulesConfig? exitRules,
    double? initialCapitalEuro,
    DateTime? updatedAt,
  }) {
    return StrategyConfigModel(
      userId: userId ?? this.userId,
      timeframes: timeframes ?? this.timeframes,
      indicators: indicators ?? this.indicators,
      filters: filters ?? this.filters,
      exitRules: exitRules ?? this.exitRules,
      initialCapitalEuro: initialCapitalEuro ?? this.initialCapitalEuro,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// TIMEFRAME GLOBALI
// ============================================================================
class TimeframeConfig {
  String operativo; // '10m', '15m', '30m'
  String medio; // '1h', '4h'
  String lungo; // '1d', '1w'
  String test; // 'tick', '1m'

  TimeframeConfig({
    required this.operativo,
    required this.medio,
    required this.lungo,
    required this.test,
  });

  Map<String, dynamic> toFirestore() => {
    'operativo': operativo,
    'medio': medio,
    'lungo': lungo,
    'test': test,
  };

  factory TimeframeConfig.fromFirestore(Map<String, dynamic> data) =>
      TimeframeConfig(
        operativo: data['operativo'] ?? '15m',
        medio: data['medio'] ?? '4h',
        lungo: data['lungo'] ?? '1d',
        test: data['test'] ?? '1m',
      );
}

// ============================================================================
// INDICATORI
// ============================================================================
class IndicatorConfig {
  EmaLong emaLong;
  EmaShort emaShort;
  SmaSignal smaSignal;
  RsiConfig rsi;
  MacdConfig macd;
  PivotConfig pivot;
  AdrScoreConfig adrScore;

  IndicatorConfig({
    required this.emaLong,
    required this.emaShort,
    required this.smaSignal,
    required this.rsi,
    required this.macd,
    required this.pivot,
    required this.adrScore,
  });

  Map<String, dynamic> toFirestore() => {
    'emaLong': emaLong.toFirestore(),
    'emaShort': emaShort.toFirestore(),
    'smaSignal': smaSignal.toFirestore(),
    'rsi': rsi.toFirestore(),
    'macd': macd.toFirestore(),
    'pivot': pivot.toFirestore(),
    'adrScore': adrScore.toFirestore(),
  };

  factory IndicatorConfig.fromFirestore(Map<String, dynamic> data) =>
      IndicatorConfig(
        emaLong: EmaLong.fromFirestore(data['emaLong']),
        emaShort: EmaShort.fromFirestore(data['emaShort']),
        smaSignal: SmaSignal.fromFirestore(data['smaSignal']),
        rsi: RsiConfig.fromFirestore(data['rsi']),
        macd: MacdConfig.fromFirestore(data['macd']),
        pivot: PivotConfig.fromFirestore(data['pivot']),
        adrScore: AdrScoreConfig.fromFirestore(data['adrScore']),
      );
}

class EmaLong {
  int length;
  int weight;
  bool enabled;
  String timeframe; // 'operativo', 'medio', 'lungo'
  EmaLong({
    required this.length,
    required this.weight,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'length': length,
    'weight': weight,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory EmaLong.fromFirestore(Map<String, dynamic> data) => EmaLong(
    length: data['length'],
    weight: data['weight'],
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

class EmaShort {
  int length;
  int weight;
  bool enabled;
  String timeframe;
  EmaShort({
    required this.length,
    required this.weight,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'length': length,
    'weight': weight,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory EmaShort.fromFirestore(Map<String, dynamic> data) => EmaShort(
    length: data['length'],
    weight: data['weight'],
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

class SmaSignal {
  int length;
  int weight;
  bool enabled;
  String timeframe;
  SmaSignal({
    required this.length,
    required this.weight,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'length': length,
    'weight': weight,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory SmaSignal.fromFirestore(Map<String, dynamic> data) => SmaSignal(
    length: data['length'],
    weight: data['weight'],
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

class RsiConfig {
  int length;
  int weight;
  int oversold;
  int overbought;
  bool enabled;
  String timeframe;
  RsiConfig({
    required this.length,
    required this.weight,
    required this.oversold,
    required this.overbought,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'length': length,
    'weight': weight,
    'oversold': oversold,
    'overbought': overbought,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory RsiConfig.fromFirestore(Map<String, dynamic> data) => RsiConfig(
    length: data['length'],
    weight: data['weight'],
    oversold: data['oversold'],
    overbought: data['overbought'],
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

class MacdConfig {
  int fast;
  int slow;
  int signal;
  int weight;
  bool enabled;
  String timeframe;
  MacdConfig({
    required this.fast,
    required this.slow,
    required this.signal,
    required this.weight,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'fast': fast,
    'slow': slow,
    'signal': signal,
    'weight': weight,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory MacdConfig.fromFirestore(Map<String, dynamic> data) => MacdConfig(
    fast: data['fast'],
    slow: data['slow'],
    signal: data['signal'],
    weight: data['weight'],
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

class PivotConfig {
  String type;
  int weight;
  bool enabled;
  String timeframe;
  PivotConfig({
    required this.type,
    required this.weight,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'type': type,
    'weight': weight,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory PivotConfig.fromFirestore(Map<String, dynamic> data) => PivotConfig(
    type: data['type'] ?? 'Standard',
    weight: data['weight'],
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

class AdrScoreConfig {
  int length;
  int weight;
  bool enabled;
  String timeframe;
  AdrScoreConfig({
    required this.length,
    required this.weight,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'length': length,
    'weight': weight,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory AdrScoreConfig.fromFirestore(Map<String, dynamic> data) =>
      AdrScoreConfig(
        length: data['length'],
        weight: data['weight'],
        enabled: data['enabled'] ?? true,
        timeframe: data['timeframe'] ?? 'operativo',
      );
}

// ============================================================================
// FILTRI
// ============================================================================
class FilterConfig {
  SuperTrendConfig superTrend;
  BollingerConfig bollinger;
  double maxAdrExtension;
  double minAtrLevel;
  TradingSessionConfig tradingSession;
  double maxSpreadAllowed;
  AdxConfig adx;

  FilterConfig({
    required this.superTrend,
    required this.bollinger,
    required this.maxAdrExtension,
    required this.minAtrLevel,
    required this.tradingSession,
    required this.maxSpreadAllowed,
    required this.adx,
  });

  Map<String, dynamic> toFirestore() => {
    'superTrend': superTrend.toFirestore(),
    'bollinger': bollinger.toFirestore(),
    'maxAdrExtension': maxAdrExtension,
    'minAtrLevel': minAtrLevel,
    'tradingSession': tradingSession.toFirestore(),
    'maxSpreadAllowed': maxSpreadAllowed,
    'adx': adx.toFirestore(),
  };

  factory FilterConfig.fromFirestore(Map<String, dynamic> data) => FilterConfig(
    superTrend: SuperTrendConfig.fromFirestore(data['superTrend']),
    bollinger: BollingerConfig.fromFirestore(data['bollinger']),
    maxAdrExtension: (data['maxAdrExtension'] as num).toDouble(),
    minAtrLevel: (data['minAtrLevel'] as num).toDouble(),
    tradingSession: TradingSessionConfig.fromFirestore(data['tradingSession']),
    maxSpreadAllowed: (data['maxSpreadAllowed'] as num).toDouble(),
    adx: AdxConfig.fromFirestore(data['adx']),
  );
}

class SuperTrendConfig {
  int period;
  double multiplier;
  bool enabled;
  String timeframe;
  SuperTrendConfig({
    required this.period,
    required this.multiplier,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'period': period,
    'multiplier': multiplier,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory SuperTrendConfig.fromFirestore(Map<String, dynamic> data) =>
      SuperTrendConfig(
        period: data['period'],
        multiplier: (data['multiplier'] as num).toDouble(),
        enabled: data['enabled'] ?? true,
        timeframe: data['timeframe'] ?? 'operativo',
      );
}

class BollingerConfig {
  int length;
  double std;
  bool enabled;
  String timeframe;
  BollingerConfig({
    required this.length,
    required this.std,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'length': length,
    'std': std,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory BollingerConfig.fromFirestore(Map<String, dynamic> data) =>
      BollingerConfig(
        length: data['length'],
        std: (data['std'] as num).toDouble(),
        enabled: data['enabled'] ?? true,
        timeframe: data['timeframe'] ?? 'operativo',
      );
}

class TradingSessionConfig {
  String start;
  String end;
  bool enabled;
  TradingSessionConfig({
    required this.start,
    required this.end,
    required this.enabled,
  });
  Map<String, dynamic> toFirestore() => {
    'start': start,
    'end': end,
    'enabled': enabled,
  };
  factory TradingSessionConfig.fromFirestore(Map<String, dynamic> data) =>
      TradingSessionConfig(
        start: data['start'] ?? '08:00',
        end: data['end'] ?? '20:00',
        enabled: data['enabled'] ?? true,
      );
}

class AdxConfig {
  int period;
  double threshold;
  bool filterDi;
  bool enabled;
  String timeframe;
  AdxConfig({
    required this.period,
    required this.threshold,
    required this.filterDi,
    required this.enabled,
    required this.timeframe,
  });
  Map<String, dynamic> toFirestore() => {
    'period': period,
    'threshold': threshold,
    'filterDi': filterDi,
    'enabled': enabled,
    'timeframe': timeframe,
  };
  factory AdxConfig.fromFirestore(Map<String, dynamic> data) => AdxConfig(
    period: data['period'],
    threshold: (data['threshold'] as num).toDouble(),
    filterDi: data['filterDi'] ?? false,
    enabled: data['enabled'] ?? true,
    timeframe: data['timeframe'] ?? 'operativo',
  );
}

// ============================================================================
// GESTIONE USCITE (SL/TP, break-even e trailing in ×ATR alla voce)
// ============================================================================
class ExitRulesConfig {
  int maxSimultaneousTrades;
  int activationScore;
  double slAtrMult;
  double tpAtrMult;
  /// Lotto minimo per ogni operazione (stesso per majors e coppie con JPY).
  double minLotPerTrade;
  BreakEvenConfig breakEven;
  TrailingStopConfig trailingStop;

  ExitRulesConfig({
    required this.maxSimultaneousTrades,
    required this.activationScore,
    required this.slAtrMult,
    required this.tpAtrMult,
    required this.minLotPerTrade,
    required this.breakEven,
    required this.trailingStop,
  });

  Map<String, dynamic> toFirestore() => {
    'maxSimultaneousTrades': maxSimultaneousTrades,
    'activationScore': activationScore,
    'slAtrMult': slAtrMult,
    'tpAtrMult': tpAtrMult,
    'minLotPerTrade': minLotPerTrade,
    'breakEven': breakEven.toFirestore(),
    'trailingStop': trailingStop.toFirestore(),
  };

  factory ExitRulesConfig.fromFirestore(Map<String, dynamic> data) =>
      ExitRulesConfig(
        maxSimultaneousTrades: data['maxSimultaneousTrades'] ?? 3,
        activationScore: data['activationScore'] ?? 55,
        slAtrMult: (data['slAtrMult'] as num?)?.toDouble() ?? 2.0,
        tpAtrMult: (data['tpAtrMult'] as num?)?.toDouble() ?? 4.0,
        minLotPerTrade: (data['minLotPerTrade'] as num?)?.toDouble() ?? 0.01,
        breakEven: BreakEvenConfig.fromFirestore(
          Map<String, dynamic>.from((data['breakEven'] as Map?) ?? {}),
        ),
        trailingStop: TrailingStopConfig.fromFirestore(
          Map<String, dynamic>.from((data['trailingStop'] as Map?) ?? {}),
        ),
      );
}

class BreakEvenConfig {
  bool active;
  /// Soglia in prezzo: quando (high−ingresso) buy / (ingresso−low) sell ≥ questo × ATR alla voce → break-even.
  double triggerAtrMult;
  /// Dopo il BE, SL a distanza in prezzo da ingresso = questo × ATR (cuscinetto oltre il pareggio).
  double lockAtrMult;
  BreakEvenConfig({
    required this.active,
    required this.triggerAtrMult,
    required this.lockAtrMult,
  });
  Map<String, dynamic> toFirestore() => {
    'active': active,
    'triggerAtrMult': triggerAtrMult,
    'lockAtrMult': lockAtrMult,
  };
  factory BreakEvenConfig.fromFirestore(Map<String, dynamic> data) {
    double fromLegacyTrigger(num? pips) {
      final p = pips?.toDouble();
      if (p == null) return 1.0;
      return (p / 15.0).clamp(0.01, 8.0);
    }

    double fromLegacyLock(num? pips) {
      final p = pips?.toDouble();
      if (p == null) return 0.1;
      return (p / 10.0).clamp(0.001, 2.0);
    }

    final tNew = (data['triggerAtrMult'] as num?)?.toDouble();
    final lNew = (data['lockAtrMult'] as num?)?.toDouble();
    final triggerAtrMult = (tNew != null && tNew > 0)
        ? tNew.clamp(0.01, 20.0)
        : fromLegacyTrigger(data['triggerPips'] as num?);
    final lockAtrMult = (lNew != null && lNew > 0)
        ? lNew.clamp(0.001, 20.0)
        : fromLegacyLock(data['lockProfit'] as num?);
    return BreakEvenConfig(
      active: data['active'] ?? false,
      triggerAtrMult: triggerAtrMult,
      lockAtrMult: lockAtrMult,
    );
  }
}

class TrailingStopConfig {
  bool active;
  /// Trailing attivo quando il profitto massimo da picco (buy) / trough (sell) in prezzo ≥ questo × ATR.
  double activationAtrMult;
  /// Passo minimo in prezzo (× ATR) per aggiornare lo SL rispetto al livello teorico da picco/trough.
  double stepAtrMult;
  TrailingStopConfig({
    required this.active,
    required this.activationAtrMult,
    required this.stepAtrMult,
  });
  Map<String, dynamic> toFirestore() => {
    'active': active,
    'activationAtrMult': activationAtrMult,
    'stepAtrMult': stepAtrMult,
  };
  factory TrailingStopConfig.fromFirestore(Map<String, dynamic> data) {
    double fromLegacyPips(num? pips, double defaultMult) {
      final p = pips?.toDouble();
      if (p == null) return defaultMult;
      return (p / 20.0).clamp(0.05, 8.0);
    }

    final actNew = (data['activationAtrMult'] as num?)?.toDouble();
    final stepNew = (data['stepAtrMult'] as num?)?.toDouble();
    final activationAtrMult = (actNew != null && actNew > 0)
        ? actNew.clamp(0.05, 20.0)
        : fromLegacyPips(data['activationPips'] as num?, 1.5);
    final stepAtrMult = (stepNew != null && stepNew > 0)
        ? stepNew.clamp(0.05, 20.0)
        : fromLegacyPips(data['stepPips'] as num?, 1.0);
    return TrailingStopConfig(
      active: data['active'] ?? true,
      activationAtrMult: activationAtrMult,
      stepAtrMult: stepAtrMult,
    );
  }
}
