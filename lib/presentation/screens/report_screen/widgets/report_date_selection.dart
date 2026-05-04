import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';

/// Campo data compatto (etichetta in alto, valore, icona calendario in basso a destra).
class ReportDateSelectionBox extends StatelessWidget {
  final String labelUppercase;
  final DateTime? date;
  final DateFormat dateFormat;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const ReportDateSelectionBox({
    super.key,
    required this.labelUppercase,
    required this.date,
    required this.dateFormat,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  static const _border = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    final valueText =
        date != null ? dateFormat.format(date!) : placeholder;
    final showClear = date != null && onClear != null;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                showClear ? AppSpacing.s7 : AppSpacing.s4,
                AppSpacing.s3,
              ),
              decoration: BoxDecoration(
                color: AppTheme.inputFillColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          labelUppercase,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                            color: AppTheme.secondaryText.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          valueText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: date != null
                                ? AppTheme.primaryText
                                : AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: AppTheme.primaryText.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showClear)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.secondaryText.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Due campi affiancati [INIZIO] / [FINE] (stesso stile del report).
class ReportDateSelectionRow extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final DateFormat dateFormat;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback? onClearStart;
  final VoidCallback? onClearEnd;

  const ReportDateSelectionRow({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.dateFormat,
    required this.onPickStart,
    required this.onPickEnd,
    this.onClearStart,
    this.onClearEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ReportDateSelectionBox(
            labelUppercase: 'INIZIO',
            date: startDate,
            dateFormat: dateFormat,
            placeholder: '—',
            onTap: onPickStart,
            onClear: onClearStart,
          ),
        ),
        SizedBox(width: AppSpacing.s3),
        Expanded(
          child: ReportDateSelectionBox(
            labelUppercase: 'FINE',
            date: endDate,
            dateFormat: dateFormat,
            placeholder: '—',
            onTap: onPickEnd,
            onClear: onClearEnd,
          ),
        ),
      ],
    );
  }
}
