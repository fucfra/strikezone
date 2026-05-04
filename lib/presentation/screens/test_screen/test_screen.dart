import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:strikezone/presentation/screens/test_screen/test_screen_view_model.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../report_screen/report_view_model.dart';
import '../report_screen/widgets/report_date_selection.dart';
import '../../widgets/custom_bottom_nav_bar.dart';
import '../../widgets/neon_report_style.dart';
import '../../widgets/report_filter_chip_panel.dart';

class TestScreen extends StatelessWidget {
  const TestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TestViewModel(),
      child: const TestView(),
    );
  }
}

class TestView extends StatelessWidget {
  const TestView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TestViewModel>();
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'SEGNALI',
          style: TextStyle(
            color: AppTheme.accentGreen,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 2.5,
            shadows: AppTheme.neonTextGlow(),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.panelBorderMuted.withValues(alpha: 0.65),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pageScrollBottomLoose,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionCaps('PARAMETRI BACKTEST'),
            AppSpacing.gapSectionLg,
            ReportFilterChipPanel(
              sectionTitle: 'COPPIA VALUTARIA',
              chips: [
                for (final epic in kReportFilterEpics)
                  NeonChoiceChip(
                    fillWidth: true,
                    label: ReportViewModel.formatEpicLabel(epic),
                    selected: vm.selectedPair == epic,
                    onTap: () => vm.setSelectedPair(epic),
                  ),
              ],
            ),
            AppSpacing.gapSectionLg,
            const NeonSectionTitle('PERIODO'),
            AppSpacing.gapS2,
            ReportDateSelectionRow(
              startDate: vm.startDate,
              endDate: vm.endDate,
              dateFormat: dateFormat,
              onPickStart: () => _pickStart(context, vm),
              onPickEnd: () => _pickEnd(context, vm),
              onClearStart: () => vm.setStartDate(null),
              onClearEnd: () => vm.setEndDate(null),
            ),
            AppSpacing.gapS6,
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: vm.isLoading ? null : () => vm.runTest(),
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: vm.isLoading
                      ? AppTheme.secondaryText
                      : AppTheme.accentGreen,
                  size: 28,
                ),
                label: Text(
                  'AVVIA TEST',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: vm.isLoading
                        ? AppTheme.secondaryText
                        : AppTheme.accentGreen,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: vm.isLoading
                        ? AppTheme.panelBorderMuted
                        : AppTheme.accentGreen,
                    width: 1.5,
                  ),
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (vm.isLoading) ...[
              AppSpacing.gapSectionLg,
              const LinearProgressIndicator(
                color: AppTheme.accentGreen,
                backgroundColor: AppTheme.inputFillColor,
              ),
              if (vm.backtestProgressTitle != null) ...[
                AppSpacing.gapSection,
                Text(
                  vm.backtestProgressTitle!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryText,
                  ),
                ),
              ],
              if (vm.backtestProgressSubtitle != null) ...[
                AppSpacing.gapS2,
                Text(
                  vm.backtestProgressSubtitle!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondaryText.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ],
            if (vm.status == TestStatus.success) ...[
              AppSpacing.gapSectionLg,
              Container(
                width: double.infinity,
                padding: AppSpacing.inputTouch,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.black.withValues(alpha: 0.88),
                      size: 22,
                    ),
                    SizedBox(width: AppSpacing.s3),
                    Flexible(
                      child: Text(
                        'TEST COMPLETATO CON SUCCESSO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.black.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (vm.lastSignalCount != null) ...[
                AppSpacing.gapSectionLg,
                _signalsGeneratedBox(vm.lastSignalCount!),
              ],
            ],
            if (vm.status == TestStatus.error && vm.errorMessage.isNotEmpty) ...[
              AppSpacing.gapSection,
              Container(
                width: double.infinity,
                padding: AppSpacing.card,
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.accentRed.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  vm.errorMessage,
                  style: const TextStyle(
                    color: AppTheme.accentRed,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
            if (vm.logs.isNotEmpty &&
                (vm.status == TestStatus.error ||
                    (vm.status == TestStatus.success &&
                        (vm.lastSignalCount ?? 0) == 0))) ...[
              AppSpacing.gapSection,
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Dettagli tecnici',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryText.withValues(alpha: 0.95),
                    ),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 220),
                      padding: EdgeInsets.all(AppSpacing.s3),
                      decoration: BoxDecoration(
                        color: AppTheme.inputFillColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.panelBorderMuted),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: vm.logs
                              .map(
                                (log) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.s1,
                                  ),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.35,
                                      color: AppTheme.secondaryText
                                          .withValues(alpha: 0.95),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              context.go(AppRouter.reportRoute);
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

  Future<void> _pickStart(BuildContext context, TestViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.startDate ??
          DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) vm.setStartDate(picked);
  }

  Future<void> _pickEnd(BuildContext context, TestViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) vm.setEndDate(picked);
  }

  Widget _sectionCaps(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppTheme.secondaryText.withValues(alpha: 0.92),
      ),
    );
  }

  Widget _signalsGeneratedBox(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s5 + AppSpacing.s2,
        horizontal: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: AppTheme.inputFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentGreen.withValues(alpha: 0.75),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentGreen.withValues(alpha: 0.14),
            blurRadius: 22,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentGreen,
              height: 1,
              shadows: AppTheme.neonTextGlow(blurInner: 12, blurOuter: 24),
            ),
          ),
          AppSpacing.gapS3,
          Text(
            'SEGNALI GENERATI',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: AppTheme.accentGreen.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
