import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Titolo sezione maiuscolo (stile report / terminale).
class NeonSectionTitle extends StatelessWidget {
  final String text;

  const NeonSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppTheme.secondaryText.withValues(alpha: 0.92),
      ),
    );
  }
}

/// Chip selezionabile neon (stesso stile [ReportScreen]).
class NeonChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  /// Se true (es. in [Row] con [Expanded]), occupa tutta la larghezza disponibile.
  final bool fillWidth;

  const NeonChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: fillWidth ? double.infinity : null,
          alignment: fillWidth ? Alignment.center : null,
          padding: AppSpacing.inputTouch,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentGreen : AppTheme.inputFillColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  selected ? AppTheme.accentGreen : AppTheme.panelBorderMuted,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: fillWidth ? TextAlign.center : null,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.black : AppTheme.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
