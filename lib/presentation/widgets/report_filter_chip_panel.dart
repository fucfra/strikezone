import 'package:flutter/cupertino.dart';

import '../../core/theme/app_theme.dart';
import 'neon_report_style.dart';

/// Box filtri report/storico: titolo sezione + chip in riga; stesso stile del report.
class ReportFilterChipPanel extends StatelessWidget {
  static const Color _panelBorder = Color(0xFF1E293B);
  static const Color _panelBg = Color(0xFF020617);

  final String sectionTitle;
  final List<Widget> chips;

  const ReportFilterChipPanel({
    super.key,
    required this.sectionTitle,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _panelBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeonSectionTitle(sectionTitle),
          AppSpacing.gapS2,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: chips[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Avviso in stile iOS ([CupertinoAlertDialog]) se non è possibile deselezionare l’ultima coppia.
Future<void> showPairFilterRequiredNotice(
  BuildContext context, {
  required String message,
}) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('Coppie valutarie'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
