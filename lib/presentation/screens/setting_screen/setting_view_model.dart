import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:strikezone/core/config/firebase_runtime_config.dart';
import 'package:strikezone/firebase_options.dart';

enum SettingsStatus { idle, loading, success, error }

class SettingsViewModel extends ChangeNotifier {
  SettingsStatus _status = SettingsStatus.idle;
  String _errorMessage = '';
  String _successMessage = '';

  final apiKeyController = TextEditingController();
  final loginController = TextEditingController();
  final passwordController = TextEditingController();

  bool _obscureApiKey = true;
  bool _obscurePassword = true;

  SettingsViewModel() {
    loadCredentials();
  }

  SettingsStatus get status => _status;
  String get errorMessage => _errorMessage;
  String get successMessage => _successMessage;

  /// True solo durante salvataggio o cancellazione Capital (il GET iniziale non usa `loading`).
  bool get isLoading => _status == SettingsStatus.loading;
  bool get obscureApiKey => _obscureApiKey;
  bool get obscurePassword => _obscurePassword;

  Uri _functionUri(String functionName) {
    return Uri.parse(
      FirebaseRuntimeConfig.onRequestFunctionUrl(
        projectId: DefaultFirebaseOptions.currentPlatform.projectId,
        functionName: functionName,
      ),
    );
  }

  void toggleObscureApiKey() {
    _obscureApiKey = !_obscureApiKey;
    notifyListeners();
  }

  void toggleObscurePassword() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  Future<void> loadCredentials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final idToken = await user.getIdToken();
      final response = await http.post(
        _functionUri('get_capital_credentials'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          apiKeyController.text = _obfuscate(data['apiKey'] ?? '');
          loginController.text = data['login'] ?? '';
          passwordController.text = _obfuscate(data['password'] ?? '');
        }
        notifyListeners();
      } else {
        _setError('Impossibile recuperare le credenziali.');
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> saveCredentials(
    String apiKey,
    String login,
    String password,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _setStatus(SettingsStatus.loading);
    try {
      final idToken = await user.getIdToken();
      final response = await http.post(
        _functionUri('save_capital_credentials'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'apiKey': apiKey,
          'login': login,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        apiKeyController.text = _obfuscate(apiKey);
        passwordController.text = _obfuscate(password);
        loginController.text = login;
        _successMessage = 'Credenziali salvate con successo.';
        _errorMessage = '';
        _setStatus(SettingsStatus.success);
      } else {
        final errorBody = jsonDecode(response.body);
        _setError(errorBody['message'] ?? 'Errore nel salvataggio.');
      }
    } catch (e) {
      _setError(e.toString());
    } finally {
      // Dopo 2 secondi, torna a idle ma mantiene il success message
      if (_status == SettingsStatus.success) {
        Future.delayed(const Duration(seconds: 2), () {
          if (_status == SettingsStatus.success) {
            _setStatus(SettingsStatus.idle);
          }
        });
      } else {
        _setStatus(SettingsStatus.idle);
      }
    }
  }

  Future<void> deleteCredentials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _setStatus(SettingsStatus.loading);
    try {
      final idToken = await user.getIdToken();
      final response = await http.post(
        _functionUri('delete_capital_credentials'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

      if (response.statusCode == 200) {
        apiKeyController.clear();
        loginController.clear();
        passwordController.clear();
        _successMessage = 'Credenziali cancellate con successo.';
        _errorMessage = '';
        _setStatus(SettingsStatus.success);
      } else {
        _setError('Errore durante la cancellazione.');
      }
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (_status == SettingsStatus.success) {
        Future.delayed(const Duration(seconds: 2), () {
          if (_status == SettingsStatus.success) {
            _setStatus(SettingsStatus.idle);
          }
        });
      } else {
        _setStatus(SettingsStatus.idle);
      }
    }
  }

  void clearSuccessMessage() {
    _successMessage = '';
    notifyListeners();
  }

  String _obfuscate(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 4) return '*' * value.length;
    return '*' * (value.length - 4) + value.substring(value.length - 4);
  }

  void _setStatus(SettingsStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _status = SettingsStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    apiKeyController.dispose();
    loginController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
