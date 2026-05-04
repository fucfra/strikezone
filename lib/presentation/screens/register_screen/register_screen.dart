import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/auth_repository.dart';
import 'register_view_model.dart';
import 'widgets/full_name_input.dart';
import 'widgets/confirm_password_input.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/strikezone_brand_logo.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final vm = RegisterViewModel(
          authRepository: context.read<AuthRepository>(),
        );
        vm.onSuccess = () {
          // Dopo la registrazione, torna al login
          context.go(AppRouter.loginRoute);
        };
        return vm;
      },
      child: const RegisterView(),
    );
  }
}

class RegisterView extends StatelessWidget {
  const RegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RegisterViewModel>();

    // Se la registrazione ha successo, mostriamo il dialogo
    if (viewModel.isSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showActivationDialog(context, viewModel);
      });
    }

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
                    'Crea Account',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapS2,
                  const Text(
                    'Inizia a fare trading nel futuro',
                    style: TextStyle(color: AppTheme.secondaryText),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapS8,
                  FullNameInput(
                    controller: viewModel.fullNameController,
                    customValidator: viewModel.validateFullName,
                  ),
                  AppSpacing.gapSectionLg,
                  CustomTextField(
                    label: 'EMAIL',
                    hint: 'mario@personipilo.com',
                    controller: viewModel.emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: viewModel.validateEmail,
                  ),
                  AppSpacing.gapSectionLg,
                  CustomTextField(
                    label: 'PASSWORD',
                    hint: '*********',
                    controller: viewModel.passwordController,
                    obscureText: true,
                    validator: viewModel.validatePassword,
                  ),
                  AppSpacing.gapSectionLg,
                  ConfirmPasswordInput(
                    controller: viewModel.confirmPasswordController,
                    customValidator: viewModel.validateConfirmPassword,
                  ),
                  AppSpacing.gapS6,
                  if (viewModel.status == RegisterStateStatus.error)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.section),
                      child: Text(
                        viewModel.errorMessage,
                        style: const TextStyle(color: AppTheme.accentRed),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  CustomButton(
                    text: 'REGISTRATI',
                    onPressed: viewModel.isLoading
                        ? () {}
                        : () => viewModel.register(),
                    isLoading: viewModel.isLoading,
                  ),
                  AppSpacing.gapSection,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Hai già un account?',
                        style: TextStyle(color: AppTheme.secondaryText),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Accedi'),
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

  void _showActivationDialog(
    BuildContext context,
    RegisterViewModel viewModel,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Icon(
            Icons.check_circle,
            color: AppTheme.accentGreen,
            size: 48,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Registrazione completata!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              AppSpacing.gapS2,
              const Text('Account creato con successo.', textAlign: TextAlign.center),
              AppSpacing.gapS2,
              const Text(
                'Riceverai una notifica quando l\'account sarà attivato.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                viewModel.resetForm();
                Navigator.pop(context); // chiude il dialogo
                Navigator.pop(context); // torna al login
              },
              child: const Text(
                'OK',
                style: TextStyle(color: AppTheme.accentGreen),
              ),
            ),
          ],
        );
      },
    );
  }
}
