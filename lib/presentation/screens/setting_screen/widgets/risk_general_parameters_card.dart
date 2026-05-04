import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'neon_settings_controls.dart';

/// Card iniziale tab Risk: "General parameters" + quattro campi con suffisso (stile terminale).
class RiskGeneralParametersCard extends StatelessWidget {
  const RiskGeneralParametersCard({
    super.key,
    required this.maxSimultaneousTrades,
    required this.onMaxSimultaneousTradesChanged,
    required this.activationScore,
    required this.onActivationScoreChanged,
    required this.minLotPerTrade,
    required this.onMinLotPerTradeChanged,
    required this.initialCapitalEuro,
    required this.onInitialCapitalEuroChanged,
  });

  final int maxSimultaneousTrades;
  final ValueChanged<int> onMaxSimultaneousTradesChanged;
  final int activationScore;
  final ValueChanged<int> onActivationScoreChanged;
  final double minLotPerTrade;
  final ValueChanged<double> onMinLotPerTradeChanged;
  final double initialCapitalEuro;
  final ValueChanged<double> onInitialCapitalEuroChanged;

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
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: kNeonSettingsInputDecorationTheme,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NeonSettingsCardTitleRow(
              title: 'General parameters',
              leadingIcon: Icons.show_chart_rounded,
            ),
            AppSpacing.gapS3,
            NeonSettingsIntField(
              label: 'Max trades simultanei',
              suffix: 'VAL',
              value: maxSimultaneousTrades,
              min: 1,
              max: 99,
              onChanged: onMaxSimultaneousTradesChanged,
            ),
            AppSpacing.gapS3,
            NeonSettingsIntField(
              label: 'Score attivazione',
              suffix: 'PTS',
              value: activationScore,
              min: 0,
              max: 200,
              onChanged: onActivationScoreChanged,
            ),
            AppSpacing.gapS3,
            NeonSettingsDoubleField(
              label: 'Lotto minimo / operazione',
              suffix: 'LOT',
              value: minLotPerTrade,
              min: 0.01,
              max: 100.0,
              fractionDigits: 2,
              onChanged: onMinLotPerTradeChanged,
            ),
            AppSpacing.gapS3,
            NeonSettingsDoubleField(
              label: 'Capitale iniziale report',
              suffix: 'EUR',
              value: initialCapitalEuro,
              min: 0,
              max: 1e12,
              fractionDigits: 0,
              onChanged: onInitialCapitalEuroChanged,
            ),
            AppSpacing.gapS3,
            Text(
              'Capitale iniziale: usato nel Report per la curva di saldo (P&L netto mensile cumulato).',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.secondaryText.withValues(alpha: 0.92),
              ),
            ),
            AppSpacing.gapS2,
            Text(
              'Stesso lotto minimo per tutte le coppie FX, incluse le croci con JPY (es. USD/JPY, EUR/JPY).',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.secondaryText.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
