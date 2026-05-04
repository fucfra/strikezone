import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:strikezone/presentation/screens/setting_screen/setting_screen.dart';
import '../../data/repositories/auth_repository.dart';
import '../../presentation/screens/history_screen/history_screen.dart';
import '../../presentation/screens/login_screen/login_screen.dart';
import '../../presentation/screens/register_screen/register_screen.dart';
import '../../presentation/screens/report_screen/report_screen.dart';
import '../../presentation/screens/signals_screen/signals_screen.dart';
import '../../presentation/screens/test_screen/test_screen.dart';

class AppRouter {
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String signalsRoute = '/signals';
  static const String settingsRoute = '/settings';
  static const String testRoute = '/test';
  static const String historyRoute = '/history';
  static const String reportRoute = '/report';

  static GoRouter createRouter(AuthRepository authRepository) {
    return GoRouter(
      initialLocation: loginRoute,
      redirect: (context, state) {
        // Verifica lo stato di autenticazione
        final isLoggedIn = authRepository.currentUser != null;
        final isGoingToLogin = state.matchedLocation == loginRoute;
        final isGoingToRegister = state.matchedLocation == registerRoute;

        // Se non loggato e non sta andando a login/register → vai a login
        if (!isLoggedIn && !isGoingToLogin && !isGoingToRegister) {
          return loginRoute;
        }
        // Se loggato e sta andando a login o register → vai a signals
        if (isLoggedIn && (isGoingToLogin || isGoingToRegister)) {
          return signalsRoute;
        }
        // Altrimenti nessuna redirect
        return null;
      },
      routes: [
        GoRoute(
          path: loginRoute,
          name: 'login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: registerRoute,
          name: 'register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: signalsRoute,
          name: 'signals',
          builder: (context, state) => const SignalsScreen(),
          redirect: (context, state) {
            // Protezione aggiuntiva: se non loggato, rimanda a login
            final authRepository = Provider.of<AuthRepository>(
              context,
              listen: false,
            );
            if (authRepository.currentUser == null) {
              return loginRoute;
            }
            return null;
          },
        ),
        GoRoute(
          path: settingsRoute,
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
          redirect: (context, state) {
            // Protezione aggiuntiva: se non loggato, rimanda a login
            final authRepository = Provider.of<AuthRepository>(
              context,
              listen: false,
            );
            if (authRepository.currentUser == null) {
              return loginRoute;
            }
            return null;
          },
        ),
        GoRoute(
          path: testRoute,
          name: 'test',
          builder: (context, state) => const TestScreen(),
          redirect: (context, state) {
            final authRepository = Provider.of<AuthRepository>(
              context,
              listen: false,
            );
            if (authRepository.currentUser == null) return loginRoute;
            return null;
          },
        ),
        GoRoute(
          path: historyRoute,
          name: 'history',
          builder: (context, state) => const HistoryScreen(),
          redirect: (context, state) {
            final authRepository = Provider.of<AuthRepository>(
              context,
              listen: false,
            );
            if (authRepository.currentUser == null) return loginRoute;
            return null;
          },
        ),
        GoRoute(
          path: reportRoute,
          name: 'report',
          builder: (context, state) => const ReportScreen(),
          redirect: (context, state) {
            final authRepository = Provider.of<AuthRepository>(
              context,
              listen: false,
            );
            if (authRepository.currentUser == null) return loginRoute;
            return null;
          },
        ),
      ],
    );
  }
}
