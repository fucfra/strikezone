import 'package:flutter/material.dart';
import '../../../../presentation/widgets/password_field.dart';

class ConfirmPasswordInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? Function(String?)? customValidator;

  const ConfirmPasswordInput({
    super.key,
    this.controller,
    this.customValidator,
  });

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) return 'Conferma la password';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PasswordField(
      label: 'CONFERMA PASSWORD',
      hint: '*********',
      controller: controller,
      validator: customValidator ?? _defaultValidator,
    );
  }
}
