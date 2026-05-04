import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:strikezone/core/config/firebase_clients.dart';
import '../models/strategy_config_model.dart';
import 'strategy_config_repository.dart';

class StrategyConfigRepositoryImpl implements StrategyConfigRepository {
  final FirebaseFirestore _firestore;

  StrategyConfigRepositoryImpl() : _firestore = FirebaseClients.firestore();

  @override
  Future<void> saveConfig(String userId, StrategyConfigModel config) async {
    await _firestore
        .collection('strategy_configs')
        .doc(userId)
        .set(config.toFirestore(), SetOptions(merge: true));
  }

  @override
  Future<StrategyConfigModel?> loadConfig(String userId) async {
    final doc = await _firestore
        .collection('strategy_configs')
        .doc(userId)
        .get();
    if (!doc.exists) {
      return null; // nessun documento trovato
    }
    return StrategyConfigModel.fromFirestore(doc);
  }

  @override
  Future<void> resetToDefault(String userId) async {
    final defaultConfig = getDefaultConfig(userId);
    await saveConfig(userId, defaultConfig);
  }

  StrategyConfigModel getDefaultConfig(String userId) {
    return StrategyConfigModel(
      userId: userId,
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
}
