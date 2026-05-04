import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/custom_bottom_nav_bar.dart';
import '../../widgets/neon_report_style.dart';
import '../../widgets/report_filter_chip_panel.dart';
import '../../widgets/star_rating.dart';
import 'report_daily_signals_chart.dart';
import 'report_monthly_charts.dart';
import 'report_view_model.dart';
import 'widgets/report_date_selection.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportViewModel(),
      child: const ReportView(),
    );
  }
}

class ReportView extends StatelessWidget {
  const ReportView({super.key});

  /// Altezza minima comune per le card Distribuzione / Efficienza.
  static const double _distributionEfficiencyMinHeight = 328;

  static String _profitFactorLabel(double pf) {
    if (!pf.isFinite) return '∞';
    return pf.toStringAsFixed(2);
  }

  static const Color _riepilogoBlurGlowColor = Color(0xFF3CFF14);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportViewModel>();
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'REPORT',
          style: TextStyle(
            color: AppTheme.accentGreen,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 2.5,
            shadows: AppTheme.neonTextGlow(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pageScroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NeonSectionTitle('PARAMETRI REPORT'),
            AppSpacing.gapSection,
            ReportFilterChipPanel(
              sectionTitle: 'TIPO SEGNALE',
              chips: [
                NeonChoiceChip(
                  fillWidth: true,
                  label: 'Reali',
                  selected: vm.typeFilter == ReportFilterType.real,
                  onTap: () => vm.setTypeFilter(ReportFilterType.real),
                ),
                NeonChoiceChip(
                  fillWidth: true,
                  label: 'Test',
                  selected: vm.typeFilter == ReportFilterType.test,
                  onTap: () => vm.setTypeFilter(ReportFilterType.test),
                ),
              ],
            ),
            AppSpacing.gapSectionLg,
            ReportFilterChipPanel(
              sectionTitle: 'COPPIA VALUTARIA',
              chips: [
                for (final epic in kReportFilterEpics)
                  NeonChoiceChip(
                    fillWidth: true,
                    label: ReportViewModel.formatEpicLabel(epic),
                    selected: vm.selectedEpics.contains(epic),
                    onTap: () {
                      final notice = vm.toggleEpicFilter(epic);
                      if (notice != null) {
                        showPairFilterRequiredNotice(context, message: notice);
                      }
                    },
                  ),
              ],
            ),
            AppSpacing.gapSectionLg,
            NeonSectionTitle('PERIODO'),
            AppSpacing.gapS2,
            ReportDateSelectionRow(
              startDate: vm.startDate,
              endDate: vm.endDate,
              dateFormat: dateFormat,
              onPickStart: () => _pickStart(context, vm),
              onPickEnd: () => _pickEnd(context, vm),
              onClearStart: () => vm.setDateRange(null, vm.endDate),
              onClearEnd: () => vm.setDateRange(vm.startDate, null),
            ),
            AppSpacing.gapS6,
            if (vm.isLoading)
              Padding(
                padding: EdgeInsets.all(AppSpacing.s8),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.accentGreen,
                  ),
                ),
              )
            else if (vm.error != null)
              Padding(
                padding: EdgeInsets.all(AppSpacing.s6),
                child: Text(
                  'Errore: ${vm.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.accentRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (vm.totalTrades == 0)
              _emptyState()
            else
              _resultsBlock(context, vm, dateFormat),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go(AppRouter.testRoute);
              break;
            case 1:
              break;
            case 2:
              context.go(AppRouter.signalsRoute);
              break;
            case 3:
              context.go(AppRouter.historyRoute);
              break;
            case 4:
              context.go(AppRouter.settingsRoute);
              break;
          }
        },
      ),
    );
  }

  Future<void> _pickStart(BuildContext context, ReportViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.startDate ??
          DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      vm.setDateRange(picked, vm.endDate);
    }
  }

  Future<void> _pickEnd(BuildContext context, ReportViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.endDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      vm.setDateRange(vm.startDate, picked);
    }
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.s2),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s7,
        horizontal: AppSpacing.pageH,
      ),
      decoration: BoxDecoration(
        color: AppTheme.inputFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.panelBorderMuted),
      ),
      child: Text(
        'Nessun segnale nel filtro.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.secondaryText.withValues(alpha: 0.95),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _resultsBlock(
    BuildContext context,
    ReportViewModel vm,
    DateFormat dateFormat,
  ) {
    final hasMetrics = vm.metricsTradeCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _riepilogoPerformanceCard(context, vm, hasMetrics),
        AppSpacing.gapSectionLg,
        SizedBox(
          height: _distributionEfficiencyMinHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _distributionCard(vm),
              ),
            SizedBox(width: AppSpacing.s3),
            Expanded(
              child: _efficiencyCard(vm),
            ),
            ],
          ),
        ),
        AppSpacing.gapSectionLg,
        _recordsSectionDivider(),
        AppSpacing.gapSection,
        _recordsRow(context, vm, dateFormat),
        AppSpacing.gapSectionLg,
        NeonSectionTitle('ANDAMENTO MENSILE'),
        AppSpacing.gapS3,
        Container(
          decoration: BoxDecoration(
            color: AppTheme.inputFillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.accentGreen.withValues(alpha: 0.42),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGreen.withValues(alpha: 0.08),
                blurRadius: 18,
                spreadRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s5,
          ),
          child: ReportMonthlyCharts(
            points: vm.monthlyReportPoints,
            initialCapital: vm.initialCapitalEuro,
          ),
        ),
        AppSpacing.gapSectionLg,
        NeonSectionTitle('APERTURE E CHIUSURE GIORNALIERE'),
        AppSpacing.gapS3,
        Container(
          decoration: BoxDecoration(
            color: AppTheme.inputFillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.accentGreen.withValues(alpha: 0.42),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGreen.withValues(alpha: 0.08),
                blurRadius: 18,
                spreadRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s5,
          ),
          child: ReportDailySignalsLineChart(
            points: vm.dailyOpenCloseSeries,
          ),
        ),
      ],
    );
  }

  static String _eurSigned(double v, {int fractionDigits = 2}) {
    final sign = v >= 0 ? '+' : '';
    final s = v.abs().toStringAsFixed(fractionDigits).replaceFirst('.', ',');
    return '$sign$s EUR';
  }

  Widget _riepilogoPerformanceCard(
    BuildContext context,
    ReportViewModel vm,
    bool hasMetrics,
  ) {
    final net = vm.totalNetPnlEuroAfterSpread;
    final netStr = hasMetrics ? _eurSigned(net) : '—';
    final kpiDividerColor =
        AppTheme.panelBorderMuted.withValues(alpha: 0.65);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -8,
          right: -8,
          top: -8,
          bottom: -8,
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _riepilogoBlurGlowColor.withValues(alpha: 0.15),
                      width: 2.5,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: AppSpacing.card,
          decoration: BoxDecoration(
            color: AppTheme.inputFillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.accentGreen.withValues(alpha: 0.72),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGreen.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NeonSectionTitle('RIEPILOGO PERFORMANCE'),
              AppSpacing.gapS3,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        netStr,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: hasMetrics && net >= 0
                              ? AppTheme.accentGreen
                              : (hasMetrics
                                  ? AppTheme.accentRed
                                  : AppTheme.secondaryText),
                          height: 1.05,
                          shadows: hasMetrics
                              ? AppTheme.neonTextGlow(
                                  color: net >= 0
                                      ? AppTheme.accentGreen
                                      : AppTheme.accentRed,
                                  blurInner: 8,
                                  blurOuter: 16,
                                )
                              : null,
                        ),
                      ),
                      AppSpacing.gapS1,
                      Text(
                        'NET PROFIT & LOSS',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.9,
                          color: AppTheme.secondaryText.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              AppSpacing.gapSectionLg,
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _kpiMiniColumn(
                      value: hasMetrics
                          ? '${(vm.winRate * 100).toStringAsFixed(1)}%'
                          : '—',
                      label: 'WIN RATE',
                      valueColor: AppTheme.accentGreen,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: kpiDividerColor,
                  ),
                  Expanded(
                    child: _kpiMiniColumn(
                      value: hasMetrics
                          ? _profitFactorLabel(vm.profitFactor)
                          : '—',
                      label: 'PROFIT FACTOR',
                      valueColor: AppTheme.primaryText,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: kpiDividerColor,
                  ),
                  Expanded(
                    child: _kpiMiniColumn(
                      value: hasMetrics
                          ? vm.totalPips.toStringAsFixed(1)
                          : '—',
                      label: 'TOTAL PIPS',
                      valueColor: AppTheme.primaryText,
                    ),
                  ),
                ],
              ),
          AppSpacing.gapSection,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: AppTheme.accentGreen.withValues(alpha: 0.9),
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL P&L (LORDO)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.secondaryText.withValues(alpha: 0.95),
                  ),
                ),
                Text(
                  hasMetrics
                      ? _eurSigned(vm.totalPnlEuro)
                      : '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: hasMetrics && vm.totalPnlEuro >= 0
                        ? AppTheme.accentGreen
                        : (hasMetrics
                            ? AppTheme.accentRed
                            : AppTheme.secondaryText),
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapSection,
          Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.panelBorderMuted.withValues(alpha: 0.65),
          ),
          AppSpacing.gapS3,
          Text(
            'CAPITALE & RENDIMENTO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppTheme.secondaryText.withValues(alpha: 0.9),
            ),
          ),
          AppSpacing.gapS3,
          _capitalInlineRow(
            'Capitale iniziale (impostazioni)',
            _reportEuroStat(vm.initialCapitalEuro),
            null,
          ),
          AppSpacing.gapS2,
          _capitalInlineRow(
            'Saldo stimato fine periodo',
            _reportEuroStat(vm.endingEquityEuro),
            null,
          ),
          AppSpacing.gapS2,
          _capitalInlineRow(
            'Variazione vs capitale iniziale',
            _returnPercentLabel(vm),
            _returnPercentColor(vm),
          ),
            ],
          ),
        ),
      ],
    );
  }

  String _returnPercentLabel(ReportViewModel vm) {
    final pct = vm.returnPercentVsInitialCapital;
    if (pct == null) return '—';
    final sign = pct > 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(2)}%';
  }

  Color? _returnPercentColor(ReportViewModel vm) {
    final pct = vm.returnPercentVsInitialCapital;
    if (pct == null) return null;
    if (pct > 0) return AppTheme.accentGreen;
    if (pct < 0) return AppTheme.accentRed;
    return AppTheme.secondaryText;
  }

  Widget _capitalInlineRow(String label, String value, Color? valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: AppTheme.secondaryText.withValues(alpha: 0.95),
            ),
          ),
        ),
        SizedBox(width: AppSpacing.s2),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppTheme.primaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiMiniColumn({
    required String value,
    required String label,
    required Color valueColor,
  }) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        AppSpacing.gapS1,
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppTheme.secondaryText.withValues(alpha: 0.88),
          ),
        ),
      ],
    );
  }

  Widget _distributionCard(ReportViewModel vm) {
    final other = vm.metricsDistributionOtherCount;
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: AppTheme.inputFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.panelBorderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'DISTRIBUZIONE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppTheme.secondaryText.withValues(alpha: 0.92),
              ),
            ),
          ),
          AppSpacing.gapS3,
          _distRow(
            'TRADES (COORTE WIN RATE)',
            vm.metricsTradeCount.toString(),
            null,
          ),
          AppSpacing.gapS2,
          _distRow(
            'VITTORIE · TP',
            vm.metricsWinProfitTakeProfitCount.toString(),
            AppTheme.accentGreen,
          ),
          AppSpacing.gapS2,
          _distRow(
            'VITTORIE · BE / TRAILING',
            vm.metricsWinProfitBreakEvenOrTrailingCount.toString(),
            const Color(0xFF4FC3F7),
          ),
          AppSpacing.gapS2,
          _distRow(
            'PERDITE · STOP',
            vm.metricsLossStopLossHitCount.toString(),
            const Color(0xFFFF8A65),
          ),
          if (other > 0) ...[
            AppSpacing.gapS2,
            _distRow(
              'ALTRI ESITI',
              other.toString(),
              AppTheme.secondaryText,
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _distRow(String label, String value, Color? valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppTheme.secondaryText.withValues(alpha: 0.95),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? AppTheme.primaryText,
          ),
        ),
      ],
    );
  }

  Widget _efficiencyCard(ReportViewModel vm) {
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: AppTheme.inputFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.panelBorderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'EFFICIENZA',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppTheme.secondaryText.withValues(alpha: 0.92),
              ),
            ),
          ),
          AppSpacing.gapS3,
          _distRow('AVG DURATION', vm.avgOpenDurationDisplay, null),
          AppSpacing.gapS2,
          _distRow(
            'AVG OPEN / DAY',
            vm.avgOpenSignalsPerDayDisplay,
            AppTheme.primaryText,
          ),
          AppSpacing.gapS2,
          _distRow(
            'SPREAD COSTS',
            '${vm.totalSpreadPaidEuro.toStringAsFixed(2).replaceFirst('.', ',')} EUR',
            AppTheme.primaryText,
          ),
          AppSpacing.gapS2,
          _distRow(
            'VAR. SL (MEDIA)',
            vm.avgStopLossAdjustmentsDisplay,
            null,
          ),
          AppSpacing.gapS2,
          _distRow(
            'VAR. SL (TOTALE)',
            vm.totalStopLossAdjustments.toString(),
            null,
          ),
          AppSpacing.gapS2,
          _distRow(
            'VAR. SL (MAX)',
            vm.maxStopLossAdjustmentsOnSignal.toString(),
            null,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _recordsSectionDivider() {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: AppTheme.panelBorderMuted.withValues(alpha: 0.8),
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
          child: Text(
            'RECORDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppTheme.secondaryText.withValues(alpha: 0.9),
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: AppTheme.panelBorderMuted.withValues(alpha: 0.8),
            thickness: 1,
          ),
        ),
      ],
    );
  }

  int _scoreToStarRating(double score) {
    return (score / 20).round().clamp(1, 5);
  }

  Widget _recordsRow(
    BuildContext context,
    ReportViewModel vm,
    DateFormat dateFormat,
  ) {
    final gain = vm.largestNetGainExtreme;
    final loss = vm.largestNetLossExtreme;
    if (gain == null && loss == null) {
      return Text(
        'Nessun dato estremi su trade con metriche.',
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.secondaryText.withValues(alpha: 0.9),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _recordTradeBox(
            title: 'BEST TRADE',
            extreme: gain,
            dateFormat: dateFormat,
            positive: true,
          ),
        ),
        SizedBox(width: AppSpacing.s3),
        Expanded(
          child: _recordTradeBox(
            title: 'WORST TRADE',
            extreme: loss,
            dateFormat: dateFormat,
            positive: false,
          ),
        ),
      ],
    );
  }

  Widget _recordTradeBox({
    required String title,
    required ReportNetPnlExtreme? extreme,
    required DateFormat dateFormat,
    required bool positive,
  }) {
    const bestBg = Color(0xFF0F1A12);
    const worstBg = Color(0xFF1F1214);
    final accent = positive ? AppTheme.accentGreen : AppTheme.accentRed;

    if (extreme == null) {
      return Container(
        height: 168,
        padding: EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: positive ? bestBg : worstBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$title\n—',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.secondaryText.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final sign = extreme.netPnlEuro >= 0 ? '+' : '';
    final pnlShort =
        '$sign${extreme.netPnlEuro.toStringAsFixed(2).replaceFirst('.', ',')}';
    final pair = ReportViewModel.formatEpicLabel(extreme.pairEpic);
    final q = extreme.quoteCurrency?.trim();
    final pairLine = (q != null && q.isNotEmpty) ? '$pair · $q' : pair;
    final dateStr = dateFormat.format(extreme.referenceDateUtc.toLocal());

    return Container(
      constraints: const BoxConstraints(minHeight: 168),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s3,
        AppSpacing.s3,
        AppSpacing.s2,
        AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: positive ? bestBg : worstBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 14,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: accent.withValues(alpha: 0.85),
                ),
              ),
              AppSpacing.gapS2,
              Text(
                '$pnlShort €',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  height: 1,
                  shadows: AppTheme.neonTextGlow(
                    color: accent,
                    blurInner: 6,
                    blurOuter: 12,
                  ),
                ),
              ),
              AppSpacing.gapS2,
              StarRating(
                rating: _scoreToStarRating(extreme.signalScore),
                size: 16,
              ),
              AppSpacing.gapS1,
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryText.withValues(alpha: 0.92),
                ),
              ),
              AppSpacing.gapS1,
              Text(
                pairLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryText,
                ),
              ),
            ],
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Icon(
              positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 30,
              color: accent.withValues(alpha: 0.42),
            ),
          ),
        ],
      ),
    );
  }

  static String _reportEuroStat(double value) {
    final neg = value < 0;
    final s = value.abs().toStringAsFixed(2).replaceFirst('.', ',');
    return '${neg ? '-' : ''}$s €';
  }

}
