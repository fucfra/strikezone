import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/strikezone_brand_logo.dart';
import '../register_screen/register_screen.dart';
import '../reset_password_screen/reset_password_screen.dart';
import 'login_view_model.dart';
import 'widgets/email_input.dart';
import 'widgets/password_input.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final vm = LoginViewModel(
          authRepository: context.read<AuthRepository>(),
        );
        vm.onSuccess = () {
          context.go(AppRouter.signalsRoute);
        };
        return vm;
      },
      child: const LoginView(),
    );
  }
}

class LoginView extends StatelessWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<LoginViewModel>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: AppSpacing.pageAuth,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Form(
              key: viewModel.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const StrikeZoneBrandLogo(),
                  AppSpacing.gapS6,
                  Text(
                    'StrikeZone',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapS2,
                  // SOTTOTITOLO AGGIUNTO
                  Text(
                    'Accedi per gestire i tuoi asset',
                    style: const TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapS8,
                  // Email
                  EmailInput(
                    controller: viewModel.emailController,
                    customValidator: viewModel.validateEmail,
                  ),
                  AppSpacing.gapSectionLg,
                  // Password
                  PasswordInput(
                    controller: viewModel.passwordController,
                    isLogin: true,
                    customValidator: viewModel.validatePassword,
                  ),
                  AppSpacing.gapS6,
                  // Messaggio errore
                  if (viewModel.status == LoginStateStatus.error)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.section),
                      child: Text(
                        viewModel.errorMessage,
                        style: const TextStyle(color: AppTheme.accentRed),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Pulsante Accedi
                  CustomButton(
                    text: 'ACCEDI',
                    onPressed: viewModel.isLoading
                        ? () {}
                        : () {
                            viewModel.login();
                          },
                    isLoading: viewModel.isLoading,
                  ),
                  AppSpacing.gapSection,
                  // Link password dimenticata
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ResetPasswordScreen(),
                        ),
                      );
                    },
                    child: const Text('Password dimenticata?'),
                  ),
                  // Link crea account
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Non hai un account?',
                        style: TextStyle(color: AppTheme.secondaryText),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: const Text('Crea un account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
