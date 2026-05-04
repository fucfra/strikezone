import '../models/strategy_config_model.dart';

abstract class StrategyConfigRepository {
  Future<void> saveConfig(String userId, StrategyConfigModel config);
  Future<StrategyConfigModel?> loadConfig(String userId);
  Future<void> resetToDefault(String userId);
  StrategyConfigModel getDefaultConfig(String userId);
}
