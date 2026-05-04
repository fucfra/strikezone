import 'package:flutter/material.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../core/utils/validators.dart';

enum ResetPasswordStateStatus { idle, loading, success, error }

class ResetPasswordViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  ResetPasswordStateStatus _status = ResetPasswordStateStatus.idle;
  String _errorMessage = '';
  String _successMessage = '';

  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();

  ResetPasswordViewModel({required AuthRepository authRepository})
    : _authRepository = authRepository;

  ResetPasswordStateStatus get status => _status;
  String get errorMessage => _errorMessage;
  String get successMessage => _successMessage;
  bool get isLoading => _status == ResetPasswordStateStatus.loading;
  bool get isSuccess => _status == ResetPasswordStateStatus.success;

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci l\'email';
    if (!Validators.isEmail(value)) return 'Email non valida';
    return null;
  }

  Future<void> sendResetEmail() async {
    if (!formKey.currentState!.validate()) return;

    _setStatus(ResetPasswordStateStatus.loading);
    _errorMessage = '';
    _successMessage = '';

    try {
      await _authRepository.sendPasswordResetEmail(emailController.text.trim());
      _successMessage =
          'Email di ripristino inviata! Controlla la tua casella di posta.';
      _setStatus(ResetPasswordStateStatus.success);
    } catch (e) {
      _setError(e.toString());
    }
  }

  void resetToIdle() {
    _setStatus(ResetPasswordStateStatus.idle);
    _errorMessage = '';
    _successMessage = '';
  }

  void _setStatus(ResetPasswordStateStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _status = ResetPasswordStateStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }
}
