import 'package:flutter/material.dart';
import '../../../../presentation/widgets/password_field.dart';

class PasswordInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? Function(String?)? customValidator;
  final bool isLogin;

  const PasswordInput({
    super.key,
    this.controller,
    this.customValidator,
    this.isLogin = true,
  });

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci la password';
    if (!isLogin && value.length < 6) return 'Minimo 6 caratteri';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PasswordField(
      label: 'PASSWORD',
      hint: '*********',
      controller: controller,
      validator: customValidator ?? _defaultValidator,
    );
  }
}
