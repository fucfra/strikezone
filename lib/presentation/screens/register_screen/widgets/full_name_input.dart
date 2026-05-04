import 'package:flutter/material.dart';
import '../../../../presentation/widgets/custom_text_field.dart';

class FullNameInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? Function(String?)? customValidator;

  const FullNameInput({super.key, this.controller, this.customValidator});

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) return 'Inserisci il nome completo';
    if (value.trim().split(' ').length < 2) return 'Inserisci nome e cognome';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return CustomTextField(
      label: 'NOME COMPLETO',
      hint: 'Mario Rossi',
      controller: controller,
      keyboardType: TextInputType.name,
      validator: customValidator ?? _defaultValidator,
    );
  }
}
