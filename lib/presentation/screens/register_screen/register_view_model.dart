import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../core/utils/validators.dart';
import '../../../utils/error_handler.dart';

enum RegisterStateStatus { idle, loading, success, error }

class RegisterViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  RegisterStateStatus _status = RegisterStateStatus.idle;
  String _errorMessage = '';

  final formKey = GlobalKey<FormState>();
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Callback per la navigazione dopo il successo
  VoidCallback? onSuccess;

  RegisterViewModel({required AuthRepository authRepository})
    : _authRepository = authRepository;

  RegisterStateStatus get status => _status;
  String get errorMessage => _errorMessage;
  bool get isLoading => _status == RegisterStateStatus.loading;
  bool get isSuccess => _status == RegisterStateStatus.success;

  String? validateFullName(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci il nome completo';
    if (value.trim().split(' ').length < 2) return 'Inserisci nome e cognome';
    return null;
  }

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

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Conferma la password';
    if (value != passwordController.text) return 'Le password non coincidono';
    return null;
  }

  Future<void> register() async {
    if (!formKey.currentState!.validate()) return;

    _setStatus(RegisterStateStatus.loading);
    _errorMessage = '';

    try {
      final user = await _authRepository.registerWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
        fullName: fullNameController.text.trim(),
      );
      if (user != null) {
        _setStatus(RegisterStateStatus.success);
        // Notifica al widget che la registrazione è riuscita
        onSuccess?.call();
      } else {
        _setError('Registrazione fallita');
      }
    } on FirebaseAuthException catch (e) {
      _setError(ErrorHandler.getFirebaseAuthErrorMessage(e));
    } on FirebaseException catch (e) {
      _setError(ErrorHandler.getFirestoreErrorMessage(e));
    } catch (e) {
      _setError(e.toString());
    }
  }

  void resetForm() {
    fullNameController.clear();
    emailController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
    _status = RegisterStateStatus.idle;
    _errorMessage = '';
    notifyListeners();
  }

  void _setStatus(RegisterStateStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _status = RegisterStateStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
