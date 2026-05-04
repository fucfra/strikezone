import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/auth_repository.dart';
import 'reset_password_view_model.dart';
import '../login_screen/widgets/email_input.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/strikezone_brand_logo.dart';

class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ResetPasswordViewModel(
        authRepository: context.read<AuthRepository>(),
      ),
      child: const ResetPasswordView(),
    );
  }
}

class ResetPasswordView extends StatelessWidget {
  const ResetPasswordView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ResetPasswordViewModel>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
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
                    // Titolo
                    Text(
                      'Hai dimenticato la password?',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapS3,
                    // Sottotitolo / descrizione
                    const Text(
                      'Inserisci l\'indirizzo email associato al tuo account di trading e ti invieremo un link sicuro per reimpostare la tua password.',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapS8,

                    // Email field
                    EmailInput(
                      controller: viewModel.emailController,
                      customValidator: viewModel.validateEmail,
                    ),
                    AppSpacing.gapS6,

                    // Messaggio successo
                    if (viewModel.isSuccess)
                      Container(
                        padding: EdgeInsets.all(AppSpacing.s3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.accentGreen,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          viewModel.successMessage,
                          style: const TextStyle(color: AppTheme.accentGreen),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Messaggio errore
                    if (viewModel.status == ResetPasswordStateStatus.error)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.section),
                        child: Text(
                          viewModel.errorMessage,
                          style: const TextStyle(color: AppTheme.accentRed),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    AppSpacing.gapSection,

                    // Bottone invia link
                    CustomButton(
                      text: 'Invia link di ripristino',
                      onPressed: viewModel.isLoading
                          ? () {}
                          : () {
                              viewModel.sendResetEmail();
                            },
                      isLoading: viewModel.isLoading,
                    ),

                    AppSpacing.gapS6,

                    // Link per tornare al login
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Ricordi la password?',
                          style: TextStyle(color: AppTheme.secondaryText),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // torna al login
                          },
                          child: const Text('Accedi ora'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
