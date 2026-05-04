import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'report_view_model.dart';

/// Grafico a **linee** (due serie): aperture e chiusure giornaliere (UTC).
/// Usa [LineChart] di fl_chart — non istogramma / barre.
class ReportDailySignalsLineChart extends StatelessWidget {
  final List<ReportDailyOpenClosePoint> points;

  const ReportDailySignalsLineChart({super.key, required this.points});

  static String _dayShort(DateTime d) {
    final x = d.toLocal();
    return '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Padding(
        padding: AppSpacing.card,
        child: Text(
          'Nessun dato giornaliero nel filtro attuale.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.secondaryText,
              ),
        ),
      );
    }

    var maxYRaw = 0;
    for (final p in points) {
      final m = p.opens > p.closes ? p.opens : p.closes;
      if (m > maxYRaw) maxYRaw = m;
    }
    final maxY = maxYRaw < 1 ? 4.0 : (maxYRaw * 1.15).ceilToDouble();
    final n = points.length;
    final bottomInterval = n > 18 ? (n / 6).ceilToDouble() : (n > 10 ? 2.0 : 1.0);

    final openColor = AppTheme.accentGreen;
    final closeColor = AppTheme.accentRed.withValues(alpha: 0.92);

    LineChartBarData lineFor(
      List<double> ys,
      Color color,
    ) {
      return LineChartBarData(
        spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), ys[i])],
        isCurved: false,
        isStepLineChart: false,
        color: color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }

    final opens = points.map((p) => p.opens.toDouble()).toList();
    final closes = points.map((p) => p.closes.toDouble()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Segnali aperti e chiusi per giorno (UTC)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryText,
              ),
        ),
        AppSpacing.gapS2,
        Wrap(
          spacing: AppSpacing.s4,
          runSpacing: AppSpacing.s2,
          children: [
            _legendDot(color: openColor, label: 'Aperture (giorno segnale)'),
            _legendDot(color: closeColor, label: 'Chiusure (giorno uscita)'),
          ],
        ),
        AppSpacing.gapS2,
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (n - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
                getDrawingHorizontalLine: (v) => FlLine(
                  color: AppTheme.secondaryText.withValues(alpha: 0.18),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: maxY <= 8 ? 1 : (maxY / 4).ceilToDouble(),
                    getTitlesWidget: (v, m) {
                      if (v < 0 || v > maxY) return const SizedBox.shrink();
                      if ((v - v.round()).abs() > 1e-6) return const SizedBox.shrink();
                      return Text(
                        v.round().toString(),
                        style: const TextStyle(fontSize: 9, color: AppTheme.secondaryText),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: bottomInterval,
                    getTitlesWidget: (v, m) {
                      final i = v.round();
                      if (i < 0 || i >= n) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s2),
                        child: Text(
                          _dayShort(points[i].dayUtc),
                          style: const TextStyle(fontSize: 9, color: AppTheme.secondaryText),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                lineFor(opens, openColor),
                lineFor(closes, closeColor),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    if (touchedSpots.isEmpty) return [];
                    final i = touchedSpots.first.x.toInt().clamp(0, n - 1);
                    final p = points[i];
                    final dayStr =
                        '${p.dayUtc.day.toString().padLeft(2, '0')}/${p.dayUtc.month.toString().padLeft(2, '0')}/${p.dayUtc.year}';
                    final iso =
                        '${p.dayUtc.year}-${p.dayUtc.month.toString().padLeft(2, '0')}-${p.dayUtc.day.toString().padLeft(2, '0')}';
                    final body = '$dayStr UTC ($iso)\nAperture: ${p.opens}\nChiusure: ${p.closes}';
                    return touchedSpots.map((spot) {
                      if (spot.barIndex == 0) {
                        return LineTooltipItem(
                          body,
                          const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                        );
                      }
                      return null;
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _legendDot({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.secondaryText,
          ),
        ),
      ],
    );
  }
}
