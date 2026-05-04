import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:strikezone/presentation/providers/auth_provider.dart';
import 'firebase_options.dart';
import 'core/config/firebase_runtime_config.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'data/datasources/firebase/firebase_auth_datasource.dart';
import 'data/datasources/firebase/firebase_firestore_datasource.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/auth_repository_impl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  final FirebaseApp app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (FirebaseRuntimeConfig.useEmulator) {
    final String host = FirebaseRuntimeConfig.emulatorHost;
    FirebaseAuth.instance.useAuthEmulator(
      host,
      FirebaseRuntimeConfig.authEmulatorPort,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      host,
      FirebaseRuntimeConfig.functionsEmulatorPort,
    );
    FirebaseFirestore.instanceFor(
      app: app,
      databaseId: FirebaseRuntimeConfig.firestoreDatabaseId,
    ).useFirestoreEmulator(host, FirebaseRuntimeConfig.firestoreEmulatorPort);

    if (kDebugMode) {
      print(
        'Firebase emulator attivo -> host=$host '
        'auth=${FirebaseRuntimeConfig.authEmulatorPort} '
        'functions=${FirebaseRuntimeConfig.functionsEmulatorPort} '
        'firestore(${FirebaseRuntimeConfig.firestoreDatabaseId})=${FirebaseRuntimeConfig.firestoreEmulatorPort}',
      );
    }
  }

  await PushNotificationService.instance.initialize();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      PushNotificationService.instance.syncTokenForCurrentUser();
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CustomAuthProvider()),
        Provider<FirebaseAuthDataSource>(
          create: (_) => FirebaseAuthDataSource(),
        ),
        Provider<FirebaseFirestoreDataSource>(
          create: (_) => FirebaseFirestoreDataSource(),
        ),
        Provider<AuthRepository>(
          create: (context) => AuthRepositoryImpl(
            authDataSource: context.read<FirebaseAuthDataSource>(),
            firestoreDataSource: context.read<FirebaseFirestoreDataSource>(),
          ),
        ),
      ],
      child: Consumer<AuthRepository>(
        builder: (context, authRepository, _) {
          return MaterialApp.router(
            title: 'StrikeZone',
            theme: AppTheme.darkTheme(),
            scaffoldMessengerKey:
                PushNotificationService.scaffoldMessengerKey,
            routerConfig: AppRouter.createRouter(authRepository),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
