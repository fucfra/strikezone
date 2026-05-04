import 'package:strikezone/core/firebase/cloud_functions_bridge.dart';
import 'package:strikezone/data/repositories/secure_credentials_repository.dart';

class SecureCredentialsRepositoryImpl implements SecureCredentialsRepository {
  @override
  Future<void> saveCredentials(
    String userId,
    Map<String, String> credentials,
  ) async {
    await CloudFunctionsBridge.callJsonMap(
      'saveCapitalCredentials',
      {
        'userId': userId,
        'apiKey': credentials['apiKey'],
        'login': credentials['login'],
        'password': credentials['password'],
      },
      timeout: const Duration(seconds: 90),
    );
  }

  @override
  Future<Map<String, String>?> getCredentials(String userId) async {
    final data = await CloudFunctionsBridge.callJsonMap(
      'getCapitalCredentials',
      {'userId': userId},
      timeout: const Duration(seconds: 60),
    );
    if (data['exists'] == true) {
      return {
        'apiKey': '${data['apiKey']}',
        'login': '${data['login']}',
        'password': '${data['password']}',
      };
    }
    return null;
  }

  @override
  Future<void> deleteCredentials(String userId) async {
    await CloudFunctionsBridge.callJsonMap(
      'deleteCapitalCredentials',
      {'userId': userId},
      timeout: const Duration(seconds: 60),
    );
  }
}
