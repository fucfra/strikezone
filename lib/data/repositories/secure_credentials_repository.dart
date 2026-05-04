abstract class SecureCredentialsRepository {
  Future<void> saveCredentials(String userId, Map<String, String> credentials);
  Future<Map<String, String>?> getCredentials(String userId);
  Future<void> deleteCredentials(String userId);
}
