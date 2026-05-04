import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

// --- Palette (allineata a General Parameters / card indicatori) ---

abstract final class NeonSettingTokens {
  NeonSettingTokens._();

  static const Color cardFill = Color(0xFF0A1006);
  static const Color cellFill = Color(0xFF050910);
  static const Color cellBorder = Color(0xFF273549);
}

/// Decorazione campi dentro la shell (nessun bordo interno M3).
const InputDecoration kNeonSettingsTextFieldDecoration = InputDecoration(
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  isDense: true,
  contentPadding: EdgeInsets.zero,
);

const InputDecorationThemeData kNeonSettingsInputDecorationTheme =
    InputDecorationThemeData(
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  filled: false,
  outlineBorder: BorderSide.none,
  activeIndicatorBorder: BorderSide.none,
);

/// Stile titolo sezione card (come "General parameters" in Risk).
TextStyle neonSettingsCardTitleTextStyle() => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      color: AppTheme.accentGreen,
      shadows: AppTheme.neonTextGlow(
        blurInner: 5,
        blurOuter: 12,
      ),
    );

/// Riga titolo: icona in cerchio + titolo maiuscolo neon + [trailing] opzionale.
class NeonSettingsCardTitleRow extends StatelessWidget {
  const NeonSettingsCardTitleRow({
    super.key,
    required this.title,
    this.leadingIcon = Icons.show_chart_rounded,
    this.trailing,
  });

  final String title;
  final IconData leadingIcon;
  final Widget? trailing;

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
            style: neonSettingsCardTitleTextStyle(),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

const TextStyle kNeonSettingsMonoValueStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w600,
  color: AppTheme.primaryText,
  fontFamily: 'monospace',
  fontFeatures: [FontFeature.tabularFigures()],
);

TextStyle _neonSuffixStyle() => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.65,
  color: AppTheme.accentGreen,
  fontFamily: 'monospace',
);

TextStyle _fieldLabelStyle() => TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.85,
  color: AppTheme.secondaryText.withValues(alpha: 0.95),
);

// --- Slider fluo (thumb quadrato + glow) ---

/// Thumb quadrato verde neon con alone.
class NeonSquareSliderThumbShape extends SliderComponentShape {
  const NeonSquareSliderThumbShape({this.side = 12});

  final double side;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(side + 16, side + 16);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? AppTheme.accentGreen;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: side, height: side),
      const Radius.circular(2),
    );

    final glow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.save();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: side + 10, height: side + 10),
        const Radius.circular(3),
      ),
      glow,
    );

    final fill = Paint()..color = color;
    canvas.drawRRect(rect, fill);
    canvas.restore();
  }
}

/// Slider con etichetta maiuscola, valore a destra (caption), track sottile e thumb quadrato fluo.
class NeonFluoSlider extends StatelessWidget {
  const NeonFluoSlider({
    super.key,
    required this.label,
    required this.valueCaption,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.uppercaseLabel = true,
  });

  final String label;
  final String valueCaption;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  /// Se false, [label] viene mostrata così com'è (es. frasi tipo "Soglia break-even").
  final bool uppercaseLabel;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                uppercaseLabel ? label.toUpperCase() : label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.55,
                  color: AppTheme.primaryText,
                ),
              ),
            ),
            Text(
              valueCaption,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.accentGreen,
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: AppTheme.neonTextGlow(
                  blurInner: 5,
                  blurOuter: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            activeTrackColor:
                AppTheme.accentGreen.withValues(alpha: 0.42),
            inactiveTrackColor:
                AppTheme.panelBorderMuted.withValues(alpha: 0.65),
            thumbColor: AppTheme.accentGreen,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const NeonSquareSliderThumbShape(side: 12),
          ),
          child: Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// --- Campi testo stile General Parameters ---

bool _hasSuffix(String? s) => s != null && s.trim().isNotEmpty;

/// Intero con shell General Parameters; [suffix] opzionale (destra, neon).
class NeonSettingsIntField extends StatelessWidget {
  const NeonSettingsIntField({
    super.key,
    required this.label,
    this.suffix,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999999,
    this.cellFill = NeonSettingTokens.cellFill,
    this.cellBorder = NeonSettingTokens.cellBorder,
  });

  final String label;
  final String? suffix;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final Color cellFill;
  final Color cellBorder;

  @override
  Widget build(BuildContext context) {
    final suf = _hasSuffix(suffix);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: _fieldLabelStyle(),
        ),
        const SizedBox(height: AppSpacing.s1),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s2,
            AppSpacing.s3,
            AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: cellFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cellBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey<int>(value),
                  initialValue: value.toString(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (raw) {
                    final v = int.tryParse(raw.trim());
                    if (v == null) return;
                    final c = v.clamp(min, max);
                    if (c != value) onChanged(c);
                  },
                  style: kNeonSettingsMonoValueStyle,
                  cursorColor: AppTheme.accentGreen,
                  decoration: kNeonSettingsTextFieldDecoration,
                ),
              ),
              if (suf) ...[
                const SizedBox(width: AppSpacing.s2),
                Text(suffix!.toUpperCase(), style: _neonSuffixStyle()),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Double con shell General Parameters; [suffix] opzionale.
class NeonSettingsDoubleField extends StatelessWidget {
  const NeonSettingsDoubleField({
    super.key,
    required this.label,
    this.suffix,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.fractionDigits,
    this.cellFill = NeonSettingTokens.cellFill,
    this.cellBorder = NeonSettingTokens.cellBorder,
  });

  final String label;
  final String? suffix;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int fractionDigits;
  final Color cellFill;
  final Color cellBorder;

  String _formatValue() {
    if (fractionDigits <= 0) {
      if (value == value.roundToDouble()) {
        return value.round().toString();
      }
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(fractionDigits);
  }

  @override
  Widget build(BuildContext context) {
    final suf = _hasSuffix(suffix);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: _fieldLabelStyle(),
        ),
        const SizedBox(height: AppSpacing.s1),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s2,
            AppSpacing.s3,
            AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: cellFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cellBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey<double>(value),
                  initialValue: _formatValue(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (raw) {
                    final n = double.tryParse(
                      raw.trim().replaceAll(',', '.'),
                    );
                    if (n == null || !n.isFinite) return;
                    final c = math.min(max, math.max(min, n));
                    if ((c - value).abs() > 1e-9) onChanged(c);
                  },
                  style: kNeonSettingsMonoValueStyle,
                  cursorColor: AppTheme.accentGreen,
                  decoration: kNeonSettingsTextFieldDecoration,
                ),
              ),
              if (suf) ...[
                const SizedBox(width: AppSpacing.s2),
                Text(suffix!.toUpperCase(), style: _neonSuffixStyle()),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Testo libero (es. orari sessione), stesso box.
class NeonSettingsPlainTextField extends StatelessWidget {
  const NeonSettingsPlainTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.cellFill = NeonSettingTokens.cellFill,
    this.cellBorder = NeonSettingTokens.cellBorder,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final Color cellFill;
  final Color cellBorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: _fieldLabelStyle(),
        ),
        const SizedBox(height: AppSpacing.s1),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s2,
            AppSpacing.s3,
            AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: cellFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cellBorder),
          ),
          child: TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            style: kNeonSettingsMonoValueStyle,
            cursorColor: AppTheme.accentGreen,
            decoration: kNeonSettingsTextFieldDecoration,
          ),
        ),
      ],
    );
  }
}

/// Campo con [TextEditingController] (credenziali): stesso box, testo monospace; [trailing] nella colonna destra.
class NeonSettingsControllerField extends StatelessWidget {
  const NeonSettingsControllerField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.trailing,
    this.cellFill = NeonSettingTokens.cellFill,
    this.cellBorder = NeonSettingTokens.cellBorder,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? trailing;
  final Color cellFill;
  final Color cellBorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: _fieldLabelStyle(),
        ),
        const SizedBox(height: AppSpacing.s1),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s2,
            AppSpacing.s2,
            AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: cellFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cellBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  style: kNeonSettingsMonoValueStyle,
                  cursorColor: AppTheme.accentGreen,
                  decoration: kNeonSettingsTextFieldDecoration,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}

/// Dropdown dentro la stessa shell (Timeframe).
class NeonSettingsDropdownField<T> extends StatelessWidget {
  const NeonSettingsDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.cellFill = NeonSettingTokens.cellFill,
    this.cellBorder = NeonSettingTokens.cellBorder,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color cellFill;
  final Color cellBorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: _fieldLabelStyle(),
        ),
        const SizedBox(height: AppSpacing.s1),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
          decoration: BoxDecoration(
            color: cellFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cellBorder),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: kNeonSettingsInputDecorationTheme,
            ),
            child: DropdownButtonFormField<T>(
              key: ValueKey<T>(value),
              initialValue: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              style: kNeonSettingsMonoValueStyle.copyWith(fontSize: 15),
              dropdownColor: NeonSettingTokens.cardFill,
              iconEnabledColor: AppTheme.accentGreen,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.s2),
                isDense: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
