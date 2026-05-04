import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'neon_settings_controls.dart';

String _atrValueCaption(double v) {
  final r = v.roundToDouble();
  if ((v - r).abs() < 1e-6) {
    return '${v.toInt()} × ATR';
  }
  final s = v.toStringAsFixed(2);
  if (s.endsWith('0')) {
    return '${v.toStringAsFixed(1)} × ATR';
  }
  return '$s × ATR';
}

/// Header card protezione: icona neon in cerchio, titolo maiuscolo chiaro, switch.
class _RiskProtectionHeader extends StatelessWidget {
  const _RiskProtectionHeader({
    required this.title,
    required this.leadingIcon,
    required this.enabled,
    required this.onEnabledChanged,
  });

  final String title;
  final IconData leadingIcon;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.accentGreen.withValues(alpha: 0.55),
            ),
          ),
          child: Icon(
            leadingIcon,
            color: AppTheme.accentGreen,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: AppTheme.primaryText,
            ),
          ),
        ),
        Switch(
          value: enabled,
          onChanged: onEnabledChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppTheme.accentGreen,
          inactiveThumbColor: AppTheme.secondaryText,
          inactiveTrackColor: AppTheme.panelBorderMuted,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

/// Shell comune: bordo neon, watermark scudo, corpo attenuato se disattivo.
class _RiskProtectionShell extends StatelessWidget {
  const _RiskProtectionShell({
    required this.title,
    required this.leadingIcon,
    required this.enabled,
    required this.onEnabledChanged,
    required this.children,
  });

  final String title;
  final IconData leadingIcon;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -6,
            right: -2,
            child: IgnorePointer(
              child: Icon(
                Icons.shield_outlined,
                size: 112,
                color: AppTheme.accentGreen.withValues(alpha: 0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RiskProtectionHeader(
                title: title,
                leadingIcon: leadingIcon,
                enabled: enabled,
                onEnabledChanged: onEnabledChanged,
              ),
              AppSpacing.gapS3,
              Opacity(
                opacity: enabled ? 1.0 : 0.42,
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _intersperse(children, const SizedBox(height: AppSpacing.s4)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static List<Widget> _intersperse(List<Widget> items, Widget spacer) {
    if (items.length <= 1) return items;
    final out = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      out.add(spacer);
      out.add(items[i]);
    }
    return out;
  }
}

/// Card break-even (layout reference: titolo chiaro + slider [NeonFluoSlider]).
class RiskBreakEvenCard extends StatelessWidget {
  const RiskBreakEvenCard({
    super.key,
    required this.active,
    required this.onActiveChanged,
    required this.triggerAtrMult,
    required this.onTriggerChanged,
    required this.lockAtrMult,
    required this.onLockChanged,
  });

  final bool active;
  final ValueChanged<bool> onActiveChanged;
  final double triggerAtrMult;
  final ValueChanged<double> onTriggerChanged;
  final double lockAtrMult;
  final ValueChanged<double> onLockChanged;

  @override
  Widget build(BuildContext context) {
    return _RiskProtectionShell(
      title: 'Break even protection',
      leadingIcon: Icons.verified_user_rounded,
      enabled: active,
      onEnabledChanged: onActiveChanged,
      children: [
        NeonFluoSlider(
          label: 'Soglia break-even',
          uppercaseLabel: false,
          valueCaption: _atrValueCaption(triggerAtrMult),
          value: triggerAtrMult,
          onChanged: onTriggerChanged,
          min: 0.1,
          max: 5.0,
          divisions: 49,
        ),
        NeonFluoSlider(
          label: 'Lock SL oltre ingresso',
          uppercaseLabel: false,
          valueCaption: _atrValueCaption(lockAtrMult),
          value: lockAtrMult,
          onChanged: onLockChanged,
          min: 0.02,
          max: 1.5,
          divisions: 74,
        ),
      ],
    );
  }
}

/// Card trailing stop (stessa struttura della break-even).
class RiskTrailingStopCard extends StatelessWidget {
  const RiskTrailingStopCard({
    super.key,
    required this.active,
    required this.onActiveChanged,
    required this.activationAtrMult,
    required this.onActivationChanged,
    required this.stepAtrMult,
    required this.onStepChanged,
  });

  final bool active;
  final ValueChanged<bool> onActiveChanged;
  final double activationAtrMult;
  final ValueChanged<double> onActivationChanged;
  final double stepAtrMult;
  final ValueChanged<double> onStepChanged;

  @override
  Widget build(BuildContext context) {
    return _RiskProtectionShell(
      title: 'Trailing stop protection',
      leadingIcon: Icons.trending_up_rounded,
      enabled: active,
      onEnabledChanged: onActiveChanged,
      children: [
        NeonFluoSlider(
          label: 'Attivazione trailing',
          uppercaseLabel: false,
          valueCaption: _atrValueCaption(activationAtrMult),
          value: activationAtrMult,
          onChanged: onActivationChanged,
          min: 0.1,
          max: 6.0,
          divisions: 59,
        ),
        NeonFluoSlider(
          label: 'Passo stop',
          uppercaseLabel: false,
          valueCaption: _atrValueCaption(stepAtrMult),
          value: stepAtrMult,
          onChanged: onStepChanged,
          min: 0.1,
          max: 4.0,
          divisions: 39,
        ),
      ],
    );
  }
}
