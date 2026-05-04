import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'neon_settings_controls.dart';

/// Card SL/TP ATR multiplier.
class RiskSlTpAtrCard extends StatelessWidget {
  const RiskSlTpAtrCard({
    super.key,
    required this.slAtrMult,
    required this.tpAtrMult,
    required this.onSlChanged,
    required this.onTpChanged,
  });

  final double slAtrMult;
  final double tpAtrMult;
  final ValueChanged<double> onSlChanged;
  final ValueChanged<double> onTpChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: NeonSettingTokens.cardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentGreen.withValues(alpha: 0.85),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeonSettingsCardTitleRow(
            title: 'SL / TP ATR',
            leadingIcon: Icons.multiline_chart_rounded,
          ),
          AppSpacing.gapS3,
          NeonFluoSlider(
            label: 'SL ATR MULTIPLIER',
            valueCaption:
                '${slAtrMult.clamp(1.0, 5.0).toStringAsFixed(1)}x',
            value: slAtrMult,
            min: 1.0,
            max: 5.0,
            divisions: 40,
            onChanged: onSlChanged,
          ),
          const SizedBox(height: AppSpacing.s4),
          NeonFluoSlider(
            label: 'TP ATR MULTIPLIER',
            valueCaption:
                '${tpAtrMult.clamp(1.0, 10.0).toStringAsFixed(1)}x',
            value: tpAtrMult,
            min: 1.0,
            max: 10.0,
            divisions: 90,
            onChanged: onTpChanged,
          ),
        ],
      ),
    );
  }
}
