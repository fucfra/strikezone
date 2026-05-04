import 'package:cloud_functions/cloud_functions.dart';

/// Punto unico per le HTTPS callable ([FirebaseFunctions.instance] = stesso usato in [main] per l’emulatore).
final class CloudFunctionsBridge {
  CloudFunctionsBridge._();

  static FirebaseFunctions get _f => FirebaseFunctions.instance;

  /// Esegue una callable e restituisce il payload come `Map<String, dynamic>`.
  static Future<Map<String, dynamic>> callJsonMap(
    String functionName,
    Map<String, dynamic> data, {
    Duration? timeout,
  }) async {
    final callable = _f.httpsCallable(functionName);
    final future = callable.call<Map<String, dynamic>>(data);
    final result =
        timeout != null ? await future.timeout(timeout) : await future;
    return Map<String, dynamic>.from(result.data);
  }
}
