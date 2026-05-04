import 'package:flutter/material.dart';
import '../../../../presentation/widgets/custom_text_field.dart';

class EmailInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? Function(String?)? customValidator;

  const EmailInput({super.key, this.controller, this.customValidator});

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci l\'email';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Email non valida';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return CustomTextField(
      label: 'EMAIL',
      hint: 'nome@esempio.it',
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      validator: customValidator ?? _defaultValidator,
    );
  }
}
