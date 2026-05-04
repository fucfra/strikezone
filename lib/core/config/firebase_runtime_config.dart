import 'package:flutter/foundation.dart';

enum FirebaseRuntimeEnv { emulator, live }

class FirebaseRuntimeConfig {
  FirebaseRuntimeConfig._();

  static const String functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );

  static const String _firestoreDatabaseIdOverride = String.fromEnvironment(
    'FIRESTORE_DATABASE_ID',
    defaultValue: '',
  );

  static const int authEmulatorPort = int.fromEnvironment(
    'FIREBASE_AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const int firestoreEmulatorPort = int.fromEnvironment(
    'FIREBASE_FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );
  static const int functionsEmulatorPort = int.fromEnvironment(
    'FIREBASE_FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );

  /// `live` | `emulator` | stringa vuota.
  ///
  /// Se **vuoto** → **emulator** su tutte le piattaforme (Auth, Firestore e Functions verso
  /// gli emulatori locali). Per usare Firebase in cloud da web o mobile:
  /// `--dart-define=APP_ENV=live`.
  ///
  /// Nota: in modalità `live` il client usa il database Firestore `strikezonedb` e le regole
  /// deployate sul progetto; se vedi `permission-denied` non stai usando l’emulatore Firestore.
  static const String _envRaw = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );
  static const String _emulatorHostOverride = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '',
  );

  static FirebaseRuntimeEnv get env {
    final v = _envRaw.toLowerCase().trim();
    if (v == 'live') return FirebaseRuntimeEnv.live;
    if (v == 'emulator') return FirebaseRuntimeEnv.emulator;
    if (v.isEmpty) return FirebaseRuntimeEnv.emulator;
    return FirebaseRuntimeEnv.emulator;
  }

  static bool get useEmulator => env == FirebaseRuntimeEnv.emulator;

  static String get firestoreDatabaseId {
    if (_firestoreDatabaseIdOverride.isNotEmpty) {
      return _firestoreDatabaseIdOverride;
    }
    // In emulator usiamo il database default, che ha import/export più affidabile.
    return useEmulator ? '(default)' : 'strikezonedb';
  }

  static String get emulatorHost {
    if (_emulatorHostOverride.isNotEmpty) {
      return _emulatorHostOverride;
    }

    // Android emulator cannot reach host machine with localhost.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    // Web + emulatori: 127.0.0.1 riduce problemi callable (MIME text/html / CORS) rispetto a "localhost".
    if (kIsWeb) {
      return '127.0.0.1';
    }
    return 'localhost';
  }

  static String onRequestFunctionUrl({
    required String projectId,
    required String functionName,
  }) {
    if (useEmulator) {
      return 'http://$emulatorHost:$functionsEmulatorPort/$projectId/$functionsRegion/$functionName';
    }
    return 'https://$functionsRegion-$projectId.cloudfunctions.net/$functionName';
  }
}
