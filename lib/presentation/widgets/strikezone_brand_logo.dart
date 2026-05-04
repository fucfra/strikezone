import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Logo StrikeZone (solo asset), usato su login / registrazione / reset password.
class StrikeZoneBrandLogo extends StatelessWidget {
  const StrikeZoneBrandLogo({
    super.key,
    this.size = 120,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/branding/app_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.show_chart,
            size: size * 0.53,
            color: AppTheme.accentGreen,
          ),
        ),
      ),
    );
  }
}
