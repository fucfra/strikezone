import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StarRating extends StatelessWidget {
  final int rating;
  final double size;
  /// Colore stelle piene (es. verde BUY / rosso SELL).
  final Color filledColor;

  const StarRating({
    super.key,
    required this.rating,
    this.size = 16,
    this.filledColor = AppTheme.accentGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating) {
          return Icon(Icons.star, color: filledColor, size: size);
        } else {
          return Icon(
            Icons.star_border,
            color: AppTheme.secondaryText,
            size: size,
          );
        }
      }),
    );
  }
}
