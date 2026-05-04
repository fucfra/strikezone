import 'package:flutter/material.dart';
import 'package:strikezone/presentation/providers/auth_provider.dart';
import '../../../../data/models/strategy_config_model.dart';
import '../../../../data/repositories/strategy_config_repository.dart';

class IndicatorsViewModel extends ChangeNotifier {
  final CustomAuthProvider _authProvider;
  final StrategyConfigRepository _repository;
  StrategyConfigModel? _config;

  IndicatorsViewModel(this._authProvider, this._repository) {
    _authProvider.addListener(_onUserChanged);
    loadConfig();
  }

  void _onUserChanged() {
    loadConfig();
  }

  StrategyConfigModel? get config => _config;

  Future<void> loadConfig() async {
    final userId = _authProvider.userId;
    if (userId == null) {
      _config = null;
      notifyListeners();
      return;
    }
    try {
      _config = await _repository.loadConfig(userId);
      if (_config == null) {
        await resetToDefault();
      }
    } catch (e, st) {
      assert(() {
        debugPrint('IndicatorsViewModel.loadConfig: $e\n$st');
        return true;
      }());
      _config ??= _repository.getDefaultConfig(userId);
    }
    notifyListeners();
  }

  Future<void> save() async {
    final userId = _authProvider.userId;
    if (userId == null || _config == null) return;
    await _repository.saveConfig(userId, _config!);
  }

  Future<void> resetToDefault() async {
    final userId = _authProvider.userId;
    if (userId == null) return;
    _config = _repository.getDefaultConfig(userId);
    await _repository.saveConfig(userId, _config!);
    notifyListeners();
  }

  // ==========================================================================
  // EMA LONG
  // ==========================================================================
  void updateEmaLongLength(int value) {
    _config?.indicators.emaLong.length = value;
    notifyListeners();
  }

  void updateEmaLongWeight(int value) {
    _config?.indicators.emaLong.weight = value;
    notifyListeners();
  }

  void updateEmaLongEnabled(bool value) {
    _config?.indicators.emaLong.enabled = value;
    notifyListeners();
  }

  void updateEmaLongTimeframe(String value) {
    _config?.indicators.emaLong.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // EMA SHORT
  // ==========================================================================
  void updateEmaShortLength(int value) {
    _config?.indicators.emaShort.length = value;
    notifyListeners();
  }

  void updateEmaShortWeight(int value) {
    _config?.indicators.emaShort.weight = value;
    notifyListeners();
  }

  void updateEmaShortEnabled(bool value) {
    _config?.indicators.emaShort.enabled = value;
    notifyListeners();
  }

  void updateEmaShortTimeframe(String value) {
    _config?.indicators.emaShort.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // SMA SIGNAL
  // ==========================================================================
  void updateSmaSignalLength(int value) {
    _config?.indicators.smaSignal.length = value;
    notifyListeners();
  }

  void updateSmaSignalWeight(int value) {
    _config?.indicators.smaSignal.weight = value;
    notifyListeners();
  }

  void updateSmaSignalEnabled(bool value) {
    _config?.indicators.smaSignal.enabled = value;
    notifyListeners();
  }

  void updateSmaSignalTimeframe(String value) {
    _config?.indicators.smaSignal.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // RSI
  // ==========================================================================
  void updateRsiLength(int value) {
    _config?.indicators.rsi.length = value;
    notifyListeners();
  }

  void updateRsiWeight(int value) {
    _config?.indicators.rsi.weight = value;
    notifyListeners();
  }

  void updateRsiOversold(int value) {
    _config?.indicators.rsi.oversold = value;
    notifyListeners();
  }

  void updateRsiOverbought(int value) {
    _config?.indicators.rsi.overbought = value;
    notifyListeners();
  }

  void updateRsiEnabled(bool value) {
    _config?.indicators.rsi.enabled = value;
    notifyListeners();
  }

  void updateRsiTimeframe(String value) {
    _config?.indicators.rsi.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // MACD
  // ==========================================================================
  void updateMacdFast(int value) {
    _config?.indicators.macd.fast = value;
    notifyListeners();
  }

  void updateMacdSlow(int value) {
    _config?.indicators.macd.slow = value;
    notifyListeners();
  }

  void updateMacdSignal(int value) {
    _config?.indicators.macd.signal = value;
    notifyListeners();
  }

  void updateMacdWeight(int value) {
    _config?.indicators.macd.weight = value;
    notifyListeners();
  }

  void updateMacdEnabled(bool value) {
    _config?.indicators.macd.enabled = value;
    notifyListeners();
  }

  void updateMacdTimeframe(String value) {
    _config?.indicators.macd.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // PIVOT
  // ==========================================================================
  void updatePivotType(String value) {
    _config?.indicators.pivot.type = value;
    notifyListeners();
  }

  void updatePivotWeight(int value) {
    _config?.indicators.pivot.weight = value;
    notifyListeners();
  }

  void updatePivotEnabled(bool value) {
    _config?.indicators.pivot.enabled = value;
    notifyListeners();
  }

  void updatePivotTimeframe(String value) {
    _config?.indicators.pivot.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // ADR SCORE
  // ==========================================================================
  void updateAdrScoreLength(int value) {
    _config?.indicators.adrScore.length = value;
    notifyListeners();
  }

  void updateAdrScoreWeight(int value) {
    _config?.indicators.adrScore.weight = value;
    notifyListeners();
  }

  void updateAdrScoreEnabled(bool value) {
    _config?.indicators.adrScore.enabled = value;
    notifyListeners();
  }

  void updateAdrScoreTimeframe(String value) {
    _config?.indicators.adrScore.timeframe = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onUserChanged);
    super.dispose();
  }
}
