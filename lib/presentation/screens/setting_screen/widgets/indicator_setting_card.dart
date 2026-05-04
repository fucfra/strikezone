import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'neon_settings_controls.dart';

/// Card indicatore: bordo neon, header con icona + titolo maiuscolo + switch, celle metriche, segmenti timeframe.
class IndicatorSettingCard extends StatelessWidget {
  const IndicatorSettingCard({
    super.key,
    required this.title,
    this.leadingIcon = Icons.show_chart_rounded,
    required this.enabled,
    required this.onEnabledChanged,
    required this.timeframeValue,
    required this.onTimeframeChanged,
    required this.parameterRows,
    this.showTimeframeLabel = false,
  });

  final String title;
  final IconData leadingIcon;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final String timeframeValue;
  final ValueChanged<String> onTimeframeChanged;
  final List<Widget> parameterRows;
  /// Mostra etichetta "TIMEFRAME" sopra i segmenti (stessi chip degli indicatori).
  final bool showTimeframeLabel;

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
              title: title,
              leadingIcon: leadingIcon,
              trailing: Switch(
                value: enabled,
                onChanged: onEnabledChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: AppTheme.accentGreen,
                inactiveThumbColor: AppTheme.secondaryText,
                inactiveTrackColor: AppTheme.panelBorderMuted,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            AppSpacing.gapS3,
            Opacity(
              opacity: enabled ? 1.0 : 0.42,
              child: IgnorePointer(
                ignoring: !enabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...parameterRows,
                    AppSpacing.gapS3,
                    if (showTimeframeLabel) ...[
                      Text(
                        'TIMEFRAME',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: AppTheme.secondaryText.withValues(alpha: 0.95),
                        ),
                      ),
                      AppSpacing.gapS1,
                    ],
                    TimeframeSegments(
                      value: timeframeValue,
                      onChanged: onTimeframeChanged,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cella numerica intera (stile General Parameters / Risk).
class NeonMetricIntCell extends StatelessWidget {
  const NeonMetricIntCell({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 9999,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return NeonSettingsIntField(
      label: label,
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
    );
  }
}

/// Slider fluo (thumb quadrato), stesso modello SL/TP ATR Risk.
class NeonSliderTile extends StatelessWidget {
  const NeonSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.divisions,
    this.fractionDigits = 2,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    final valueStr = value.clamp(min, max).toStringAsFixed(fractionDigits);
    return NeonFluoSlider(
      label: label,
      valueCaption: valueStr,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
    );
  }
}

/// Switch con etichetta (stesso stile delle card filtri).
class NeonLabeledSwitchTile extends StatelessWidget {
  const NeonLabeledSwitchTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: AppTheme.secondaryText.withValues(alpha: 0.95),
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTheme.accentGreen,
            inactiveThumbColor: AppTheme.secondaryText,
            inactiveTrackColor: AppTheme.panelBorderMuted,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// Pannello senza switch di abilitazione: stesso bordo/card degli indicatori (blocchi "altri filtri").
class NeonSettingsPanel extends StatelessWidget {
  const NeonSettingsPanel({
    super.key,
    this.title,
    this.titleIcon = Icons.tune_rounded,
    required this.children,
  });

  final String? title;
  final IconData titleIcon;
  final List<Widget> children;

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
            if (title != null) ...[
              NeonSettingsCardTitleRow(
                title: title!,
                leadingIcon: titleIcon,
              ),
              AppSpacing.gapS3,
            ],
            ..._intersperse(children, AppSpacing.gapS2),
          ],
        ),
      ),
    );
  }

  static List<Widget> _intersperse(List<Widget> items, Widget spacer) {
    if (items.isEmpty) return items;
    final out = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      out.add(spacer);
      out.add(items[i]);
    }
    return out;
  }
}

/// Campo testo compatto (sessione, orari) dentro le card filtri.
class NeonCompactTextField extends StatelessWidget {
  const NeonCompactTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return NeonSettingsPlainTextField(
      label: label,
      initialValue: initialValue,
      onChanged: onChanged,
    );
  }
}

/// Cella per valori double (stile General Parameters).
class NeonMetricDoubleCell extends StatelessWidget {
  const NeonMetricDoubleCell({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1000.0,
    this.fractionDigits = 2,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    return NeonSettingsDoubleField(
      label: label,
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      fractionDigits: fractionDigits,
    );
  }
}

/// Segmenti operativo / medio / lungo (stesso componente per indicatori e filtri).
class TimeframeSegments extends StatelessWidget {
  const TimeframeSegments({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = ['operativo', 'medio', 'lungo'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _SegmentChip(
              label: _options[i],
              selected: value == _options[i],
              onTap: () => onChanged(_options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.s3,
            horizontal: AppSpacing.s1,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppTheme.accentGreen
                  : AppTheme.panelBorderMuted.withValues(alpha: 0.5),
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.2,
              color: selected
                  ? AppTheme.accentGreen
                  : AppTheme.secondaryText.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }
}
