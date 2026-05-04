import 'package:flutter/material.dart';
import 'package:strikezone/presentation/providers/auth_provider.dart';
import '../../../../data/models/strategy_config_model.dart';
import '../../../../data/repositories/strategy_config_repository.dart';

class TimeframeViewModel extends ChangeNotifier {
  final CustomAuthProvider _authProvider;
  final StrategyConfigRepository _repository;
  StrategyConfigModel? _config;
  bool _isLoading = true;

  TimeframeViewModel(this._authProvider, this._repository) {
    _authProvider.addListener(_onUserChanged);
    loadConfig();
  }

  bool get isLoading => _isLoading;
  StrategyConfigModel? get config => _config;

  void _onUserChanged() {
    loadConfig();
  }

  Future<void> loadConfig() async {
    final userId = _authProvider.userId;
    if (userId == null) {
      _config = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      _config = await _repository.loadConfig(userId);
      if (_config == null) {
        await resetToDefault();
      }
    } catch (e, st) {
      assert(() {
        debugPrint('TimeframeViewModel.loadConfig: $e\n$st');
        return true;
      }());
      _config ??= _repository.getDefaultConfig(userId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  void updateOperativo(String value) {
    if (_config == null) return;
    _config!.timeframes.operativo = value;
    notifyListeners();
  }

  void updateMedio(String value) {
    if (_config == null) return;
    _config!.timeframes.medio = value;
    notifyListeners();
  }

  void updateLungo(String value) {
    if (_config == null) return;
    _config!.timeframes.lungo = value;
    notifyListeners();
  }

  void updateTest(String value) {
    if (_config == null) return;
    _config!.timeframes.test = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onUserChanged);
    super.dispose();
  }
}
