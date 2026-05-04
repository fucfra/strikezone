import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/trading/fx_pair_utils.dart';
import '../../../data/models/quote_model.dart';
import '../../../data/models/signal_model.dart';
import '../../../presentation/providers/market_data_provider.dart';
import '../../../presentation/widgets/custom_bottom_nav_bar.dart';
import '../../../presentation/widgets/neon_report_style.dart';
import '../../../presentation/widgets/report_filter_chip_panel.dart';
import '../../../presentation/widgets/real_signal_edit_bottom_sheet.dart';
import '../../../presentation/widgets/signal_detail_bottom_sheet.dart';
import '../../../presentation/widgets/signal_history_item.dart';
import '../report_screen/report_view_model.dart';
import '../report_screen/widgets/report_date_selection.dart';
import 'history_screen_view_model.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MarketDataProvider()),
        ChangeNotifierProvider(create: (_) => HistoryViewModel()),
      ],
      child: const HistoryView(),
    );
  }
}

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  static Future<void> _pickStart(
    BuildContext context,
    HistoryViewModel vm,
  ) async {
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

  static String _filteredSignalCountLabel(int n) {
    if (n == 0) {
      return '0 segnali corrispondenti al filtro';
    }
    if (n == 1) {
      return '1 segnale corrispondente al filtro';
    }
    return '$n segnali corrispondenti al filtro';
  }

  static Future<void> _pickEnd(
    BuildContext context,
    HistoryViewModel vm,
  ) async {
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

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HistoryViewModel>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'STORICO',
          style: TextStyle(
            color: AppTheme.accentGreen,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 2.5,
            shadows: AppTheme.neonTextGlow(),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppSpacing.pageScroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReportFilterChipPanel(
                  sectionTitle: 'TIPO SEGNALE',
                  chips: [
                    NeonChoiceChip(
                      fillWidth: true,
                      label: 'Reali',
                      selected: viewModel.typeFilter == HistoryFilterType.real,
                      onTap: () =>
                          viewModel.setTypeFilter(HistoryFilterType.real),
                    ),
                    NeonChoiceChip(
                      fillWidth: true,
                      label: 'Test',
                      selected: viewModel.typeFilter == HistoryFilterType.test,
                      onTap: () =>
                          viewModel.setTypeFilter(HistoryFilterType.test),
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
                        selected: viewModel.selectedEpics.contains(epic),
                        onTap: () {
                          final notice = viewModel.toggleEpicFilter(epic);
                          if (notice != null) {
                            showPairFilterRequiredNotice(
                              context,
                              message: notice,
                            );
                          }
                        },
                      ),
                  ],
                ),
                AppSpacing.gapSectionLg,
                const NeonSectionTitle('PERIODO'),
                AppSpacing.gapS2,
                ReportDateSelectionRow(
                  startDate: viewModel.startDate,
                  endDate: viewModel.endDate,
                  dateFormat: _dateFormat,
                  onPickStart: () => _pickStart(context, viewModel),
                  onPickEnd: () => _pickEnd(context, viewModel),
                  onClearStart: () =>
                      viewModel.setDateRange(null, viewModel.endDate),
                  onClearEnd: () =>
                      viewModel.setDateRange(viewModel.startDate, null),
                ),
                AppSpacing.gapS3,
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    viewModel.isLoading
                        ? 'Aggiornamento conteggio…'
                        : viewModel.error != null
                            ? 'Conteggio non disponibile'
                            : _filteredSignalCountLabel(
                                viewModel.signals.length,
                              ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: viewModel.isLoading || viewModel.error != null
                          ? AppTheme.secondaryText.withValues(alpha: 0.9)
                          : AppTheme.accentGreen.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildSignalList(context, viewModel)),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go(AppRouter.testRoute);
              break;
            case 1:
              context.go(AppRouter.reportRoute);
              break;
            case 2:
              context.go(AppRouter.signalsRoute);
              break;
            case 3:
              break;
            case 4:
              context.go(AppRouter.settingsRoute);
              break;
          }
        },
      ),
    );
  }

  Widget _buildSignalList(BuildContext context, HistoryViewModel viewModel) {
    if (viewModel.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentGreen),
      );
    }
    if (viewModel.error != null) {
      return Center(
        child: Padding(
          padding: AppSpacing.pageHorizontalOnly,
          child: Text(
            'Errore: ${viewModel.error}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.accentRed,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (viewModel.signals.isEmpty) {
      return Center(
        child: Padding(
          padding: AppSpacing.pageHorizontalOnly,
          child: Text(
            'Nessun segnale nel filtro attuale',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText.withValues(alpha: 0.95),
              fontSize: 14,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: AppSpacing.pageHorizontalOnly.copyWith(
        top: AppSpacing.s2,
        bottom: AppSpacing.s4,
      ),
      itemCount: viewModel.signals.length,
      itemBuilder: (context, index) {
        final signal = viewModel.signals[index];
        final market = context.watch<MarketDataProvider>();
        final epic = normalizedPairEpic(signal.pair);
        QuoteModel? quote;
        for (final q in market.liveQuotes) {
          if (normalizedPairEpic(q.epic) == epic) {
            quote = q;
            break;
          }
        }
        final showRealActions =
            signal.documentSource == SignalFirestoreCollection.live &&
                viewModel.typeFilter != HistoryFilterType.test;
        return SignalHistoryItem(
          signal: signal,
          liveQuote: quote,
          onTap: showRealActions
              ? null
              : () => showSignalDetailBottomSheet(context, signal),
          onEditRealSignal: showRealActions
              ? () => showRealSignalEditBottomSheet(
                    context,
                    signal,
                    onSubmit: ({
                      required double entryPrice,
                      required double stopLoss,
                      required bool executionConfirmed,
                      required bool clearExit,
                      double? exitPrice,
                      DateTime? exitTime,
                    }) =>
                        context.read<HistoryViewModel>().submitLiveSignalEdits(
                              signal,
                              entryPrice: entryPrice,
                              stopLoss: stopLoss,
                              executionConfirmed: executionConfirmed,
                              clearExit: clearExit,
                              exitPrice: exitPrice,
                              exitTime: exitTime,
                            ),
                  )
              : null,
          onShowIndicators: showRealActions
              ? () => showSignalDetailBottomSheet(context, signal)
              : null,
        );
      },
    );
  }
}
