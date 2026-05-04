import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'report_view_model.dart';

/// Etichette mese senza `intl` locale (evita LocaleDataException su web/hot reload).
String _reportMonthShortIt(DateTime monthUtc) {
  const names = [
    'gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic',
  ];
  final d = monthUtc.toLocal();
  final yy = d.year.remainder(100).toString().padLeft(2, '0');
  return "${names[d.month - 1]} '$yy'";
}

String _reportEuroIt(double value, {int fractionDigits = 0}) {
  final neg = value < 0;
  final s = value.abs().toStringAsFixed(fractionDigits).replaceFirst('.', ',');
  return '${neg ? '-' : ''}$s €';
}

/// Grafici redditività mensile (barre) e andamento saldo (linea).
class ReportMonthlyCharts extends StatelessWidget {
  final List<ReportMonthlyPoint> points;
  final double initialCapital;

  const ReportMonthlyCharts({
    super.key,
    required this.points,
    required this.initialCapital,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Card(
        color: AppTheme.surfaceColor,
        child: Padding(
          padding: AppSpacing.card,
          child: const Text(
            'Nessun trade con P&L simulato nel filtro attuale '
            '(scegli tipo Test o reali con realized_pnl_eur).',
            style: TextStyle(color: AppTheme.secondaryText),
          ),
        ),
      );
    }

    final equities = points.map((p) => p.equityEndEuro).toList();
    final minEq = [initialCapital, ...equities].reduce((a, b) => a < b ? a : b);
    final maxEq = [initialCapital, ...equities].reduce((a, b) => a > b ? a : b);
    final eqPad = (maxEq - minEq).abs() < 1 ? 100.0 : (maxEq - minEq) * 0.08;
    final lineMinY = minEq - eqPad;
    final lineMaxY = maxEq + eqPad;

    final nets = points.map((p) => p.netPnlEuro).toList();
    final maxNet = nets.map((e) => e.abs()).reduce((a, b) => a > b ? a : b);
    final barMaxY = maxNet < 1 ? 1.0 : maxNet * 1.15;
    final barMinY = -barMaxY;

    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s2, top: AppSpacing.s1),
          child: Text(
            t,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryText,
                ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title('Andamento saldo (capitale + P&L netto cumulato)'),
        Text(
          'Capitale iniziale: ${_reportEuroIt(initialCapital, fractionDigits: 0)}',
          style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
        ),
        AppSpacing.gapS2,
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: lineMinY,
              maxY: lineMaxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (lineMaxY - lineMinY) / 4,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: AppTheme.secondaryText.withValues(alpha: 0.2),
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
                    reservedSize: 44,
                    interval: (lineMaxY - lineMinY) / 4,
                    getTitlesWidget: (v, m) => Text(
                      _reportEuroIt(v, fractionDigits: 0),
                      style: const TextStyle(fontSize: 9, color: AppTheme.secondaryText),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: points.length > 10 ? 2 : 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s2),
                        child: Text(
                          _reportMonthShortIt(points[i].monthUtc),
                          style: const TextStyle(fontSize: 9, color: AppTheme.secondaryText),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].equityEndEuro),
                  ],
                  isCurved: true,
                  color: AppTheme.accentGreen,
                  barWidth: 2,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.accentGreen.withValues(alpha: 0.12),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((e) {
                      final i = e.x.toInt();
                      if (i < 0 || i >= points.length) return null;
                      final p = points[i];
                      return LineTooltipItem(
                        '${_reportMonthShortIt(p.monthUtc)}\n'
                        '${_reportEuroIt(p.equityEndEuro, fractionDigits: 1)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
        AppSpacing.gapSectionLg,
        title('P&L netto per mese (realized − spread)'),
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              minY: barMinY,
              maxY: barMaxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) {
                  if (v.abs() < 1e-6) {
                    return FlLine(
                      color: AppTheme.secondaryText.withValues(alpha: 0.45),
                      strokeWidth: 1.2,
                    );
                  }
                  return FlLine(
                    color: AppTheme.secondaryText.withValues(alpha: 0.15),
                    strokeWidth: 1,
                  );
                },
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
                    reservedSize: 44,
                    interval: barMaxY / 3,
                    getTitlesWidget: (v, m) => Text(
                      _reportEuroIt(v, fractionDigits: 0),
                      style: const TextStyle(fontSize: 9, color: AppTheme.secondaryText),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: points.length > 10 ? 2 : 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s2),
                        child: Text(
                          _reportMonthShortIt(points[i].monthUtc),
                          style: const TextStyle(fontSize: 9, color: AppTheme.secondaryText),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        fromY: points[i].netPnlEuro >= 0 ? 0 : points[i].netPnlEuro,
                        toY: points[i].netPnlEuro >= 0 ? points[i].netPnlEuro : 0,
                        width: points.length > 16 ? 10 : 18,
                        borderRadius: points[i].netPnlEuro >= 0
                            ? const BorderRadius.vertical(top: Radius.circular(4))
                            : const BorderRadius.vertical(
                                bottom: Radius.circular(4),
                              ),
                        color: points[i].netPnlEuro >= 0
                            ? AppTheme.accentGreen
                            : AppTheme.accentRed,
                      ),
                    ],
                  ),
              ],
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final p = points[group.x.toInt()];
                    return BarTooltipItem(
                      '${_reportMonthShortIt(p.monthUtc)}\n'
                      '${_reportEuroIt(p.netPnlEuro, fractionDigits: 1)}',
                      TextStyle(
                        color: p.netPnlEuro >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
