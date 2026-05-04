import 'package:flutter/material.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../core/utils/validators.dart';

enum LoginStateStatus { idle, loading, success, error }

class LoginViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  LoginStateStatus _status = LoginStateStatus.idle;
  String _errorMessage = '';

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  // Callback per la navigazione dopo il successo
  VoidCallback? onSuccess;

  LoginViewModel({required AuthRepository authRepository})
    : _authRepository = authRepository;

  LoginStateStatus get status => _status;
  String get errorMessage => _errorMessage;
  bool get isLoading => _status == LoginStateStatus.loading;

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci l\'email';
    if (!Validators.isEmail(value)) return 'Email non valida';
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci la password';
    if (value.length < 6) return 'Minimo 6 caratteri';
    return null;
  }

  Future<void> login() async {
    if (!formKey.currentState!.validate()) return;

    _setStatus(LoginStateStatus.loading);
    _errorMessage = '';

    try {
      final user = await _authRepository.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      if (user != null) {
        _setStatus(LoginStateStatus.success);
        // Notifica al widget che il login è riuscito
        onSuccess?.call();
      } else {
        _setError('Credenziali errate');
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _setError('Inserisci l\'email per il reset');
      return;
    }
    try {
      await _authRepository.sendPasswordResetEmail(email);
      _setError('');
      // Qui potresti mostrare un messaggio di conferma
    } catch (e) {
      _setError('Errore reset: $e');
    }
  }

  void _setStatus(LoginStateStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _status = LoginStateStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
