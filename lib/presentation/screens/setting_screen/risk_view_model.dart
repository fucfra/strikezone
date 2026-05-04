import 'package:flutter/material.dart';
import 'package:strikezone/presentation/providers/auth_provider.dart';
import '../../../core/trading/min_lot_per_trade.dart';
import '../../../data/models/strategy_config_model.dart';
import '../../../data/repositories/strategy_config_repository.dart';

class RiskViewModel extends ChangeNotifier {
  final CustomAuthProvider _authProvider;
  final StrategyConfigRepository _repository;
  StrategyConfigModel? _config;

  RiskViewModel(this._authProvider, this._repository) {
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
        debugPrint('RiskViewModel.loadConfig: $e\n$st');
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

  // Metodi di aggiornamento dei campi
  void updateMaxSimultaneousTrades(int value) {
    _config?.exitRules.maxSimultaneousTrades = value;
    notifyListeners();
  }

  void updateActivationScore(int value) {
    _config?.exitRules.activationScore = value;
    notifyListeners();
  }

  void updateSlAtrMult(double value) {
    _config?.exitRules.slAtrMult = value;
    notifyListeners();
  }

  void updateTpAtrMult(double value) {
    _config?.exitRules.tpAtrMult = value;
    notifyListeners();
  }

  void updateMinLotPerTrade(double value) {
    _config?.exitRules.minLotPerTrade = effectiveMinLotPerTrade(
      configured: value,
    );
    notifyListeners();
  }

  void updateInitialCapitalEuro(double value) {
    final v = value.isFinite ? value.clamp(0.0, 1e12) : 10000.0;
    _config?.initialCapitalEuro = v;
    notifyListeners();
  }

  void updateBreakEvenActive(bool value) {
    _config?.exitRules.breakEven.active = value;
    notifyListeners();
  }

  void updateBreakEvenTriggerAtrMult(double value) {
    _config?.exitRules.breakEven.triggerAtrMult = value;
    notifyListeners();
  }

  void updateBreakEvenLockAtrMult(double value) {
    _config?.exitRules.breakEven.lockAtrMult = value;
    notifyListeners();
  }

  void updateTrailingStopActive(bool value) {
    _config?.exitRules.trailingStop.active = value;
    notifyListeners();
  }

  void updateTrailingStopActivationAtrMult(double value) {
    _config?.exitRules.trailingStop.activationAtrMult = value;
    notifyListeners();
  }

  void updateTrailingStopStepAtrMult(double value) {
    _config?.exitRules.trailingStop.stepAtrMult = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onUserChanged);
    super.dispose();
  }
}
