import 'package:flutter/material.dart';
import 'package:strikezone/presentation/providers/auth_provider.dart';
import '../../../../data/models/strategy_config_model.dart';
import '../../../../data/repositories/strategy_config_repository.dart';

class FiltersViewModel extends ChangeNotifier {
  final CustomAuthProvider _authProvider;
  final StrategyConfigRepository _repository;
  StrategyConfigModel? _config;

  FiltersViewModel(this._authProvider, this._repository) {
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
        debugPrint('FiltersViewModel.loadConfig: $e\n$st');
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
  // SUPERTREND
  // ==========================================================================
  void updateSuperTrendPeriod(int value) {
    _config?.filters.superTrend.period = value;
    notifyListeners();
  }

  void updateSuperTrendMultiplier(double value) {
    _config?.filters.superTrend.multiplier = value;
    notifyListeners();
  }

  void updateSuperTrendEnabled(bool value) {
    _config?.filters.superTrend.enabled = value;
    notifyListeners();
  }

  void updateSuperTrendTimeframe(String value) {
    _config?.filters.superTrend.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // BOLLINGER
  // ==========================================================================
  void updateBollingerLength(int value) {
    _config?.filters.bollinger.length = value;
    notifyListeners();
  }

  void updateBollingerStd(double value) {
    _config?.filters.bollinger.std = value;
    notifyListeners();
  }

  void updateBollingerEnabled(bool value) {
    _config?.filters.bollinger.enabled = value;
    notifyListeners();
  }

  void updateBollingerTimeframe(String value) {
    _config?.filters.bollinger.timeframe = value;
    notifyListeners();
  }

  // ==========================================================================
  // MAX ADR EXTENSION
  // ==========================================================================
  void updateMaxAdrExtension(double value) {
    _config?.filters.maxAdrExtension = value;
    notifyListeners();
  }

  // ==========================================================================
  // MIN ATR LEVEL
  // ==========================================================================
  void updateMinAtrLevel(double value) {
    _config?.filters.minAtrLevel = value;
    notifyListeners();
  }

  // ==========================================================================
  // TRADING SESSION
  // ==========================================================================
  void updateTradingSessionStart(String value) {
    _config?.filters.tradingSession.start = value;
    notifyListeners();
  }

  void updateTradingSessionEnd(String value) {
    _config?.filters.tradingSession.end = value;
    notifyListeners();
  }

  void updateTradingSessionEnabled(bool value) {
    _config?.filters.tradingSession.enabled = value;
    notifyListeners();
  }

  // ==========================================================================
  // MAX SPREAD ALLOWED
  // ==========================================================================
  void updateMaxSpreadAllowed(double value) {
    _config?.filters.maxSpreadAllowed = value;
    notifyListeners();
  }

  // ==========================================================================
  // ADX
  // ==========================================================================
  void updateAdxPeriod(int value) {
    _config?.filters.adx.period = value;
    notifyListeners();
  }

  void updateAdxThreshold(double value) {
    _config?.filters.adx.threshold = value;
    notifyListeners();
  }

  void updateAdxFilterDi(bool value) {
    _config?.filters.adx.filterDi = value;
    notifyListeners();
  }

  void updateAdxEnabled(bool value) {
    _config?.filters.adx.enabled = value;
    notifyListeners();
  }

  void updateAdxTimeframe(String value) {
    _config?.filters.adx.timeframe = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onUserChanged);
    super.dispose();
  }
}
