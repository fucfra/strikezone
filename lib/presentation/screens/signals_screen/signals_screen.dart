// lib/presentation/screens/signals_screen/signals_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/trading/fx_pair_utils.dart';
import '../../../data/models/quote_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/signal_repository.dart';
import '../../../data/repositories/signal_repository_impl.dart';
import '../../../presentation/providers/market_data_provider.dart'
    show MarketDataProvider, MarketDataStatus;
import '../../../presentation/widgets/custom_bottom_nav_bar.dart';
import '../../../presentation/widgets/live_quotation_card.dart';
import '../../../presentation/widgets/neon_report_style.dart';
import '../../../presentation/widgets/real_signal_edit_bottom_sheet.dart';
import '../../../presentation/widgets/signal_detail_bottom_sheet.dart';
import '../../../presentation/widgets/signal_history_item.dart';
import 'signals_view_model.dart';

class SignalsScreen extends StatelessWidget {
  const SignalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MarketDataProvider()),
        Provider<SignalRepository>(create: (_) => SignalRepositoryImpl()),
        ChangeNotifierProvider(
          create: (context) =>
              SignalsViewModel(context.read<SignalRepository>()),
        ),
      ],
      child: const SignalsView(),
    );
  }
}

class SignalsView extends StatelessWidget {
  const SignalsView({super.key});

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final signalsViewModel = context.watch<SignalsViewModel>();
    final quotes = marketProvider.liveQuotes;
    final active = signalsViewModel.activeSignals;

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
        actions: [
          IconButton(
            onPressed: () {
              // TODO: notifiche future
            },
            icon: Icon(
              Icons.notifications_none,
              color: AppTheme.primaryText.withValues(alpha: 0.9),
            ),
          ),
          TextButton(
            onPressed: () async {
              final authRepo = Provider.of<AuthRepository>(
                context,
                listen: false,
              );
              await authRepo.signOut();
              if (context.mounted) {
                context.go(AppRouter.loginRoute);
              }
            },
            child: Text(
              'LOGOUT',
              style: TextStyle(
                color: AppTheme.accentGreen.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accentGreen,
        onRefresh: () async {
          marketProvider.refreshConnection();
          signalsViewModel.refreshSignals();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.pageScroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(child: NeonSectionTitle('LIVE QUOTATIONS')),
                  Text(
                    'Auto ogni ${MarketDataProvider.quoteAutoRefreshInterval.inSeconds}s',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondaryText.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapSection,

              if (marketProvider.status == MarketDataStatus.connecting)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: AppTheme.accentGreen,
                        ),
                        AppSpacing.gapS2,
                        Text(
                          'Connessione in corso...',
                          style: TextStyle(
                            color: AppTheme.secondaryText.withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (marketProvider.status == MarketDataStatus.error)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppTheme.accentRed,
                          size: 48,
                        ),
                        AppSpacing.gapS2,
                        Text(
                          marketProvider.errorMessage ??
                              'Errore di connessione',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.primaryText),
                        ),
                        AppSpacing.gapSection,
                        ElevatedButton(
                          onPressed: () => marketProvider.reconnect(),
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (quotes.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: Text(
                      'Nessuna quotazione disponibile',
                      style: TextStyle(
                        color: AppTheme.secondaryText.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: quotes.map((quote) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppSpacing.section),
                      child: LiveQuotationCard(quote: quote),
                    );
                  }).toList(),
                ),

              AppSpacing.gapSection,
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: signalsViewModel.isCapitalEvalLoading
                      ? null
                      : () async {
                          await context
                              .read<SignalsViewModel>()
                              .runLiveStrategyFromCapital(
                                pairs: SignalsViewModel.defaultLiveEvaluationPairs,
                              );
                        },
                  icon: signalsViewModel.isCapitalEvalLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentGreen.withValues(alpha: 0.9),
                          ),
                        )
                      : Icon(
                          Icons.auto_graph_rounded,
                          color: AppTheme.accentGreen.withValues(alpha: 0.95),
                        ),
                  label: Text(
                    signalsViewModel.isCapitalEvalLoading
                        ? 'VALUTAZIONE IN CORSO…'
                        : 'VALUTA STRATEGIA (CAPITAL.COM)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: signalsViewModel.isCapitalEvalLoading
                          ? AppTheme.secondaryText
                          : AppTheme.accentGreen,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: signalsViewModel.isCapitalEvalLoading
                          ? AppTheme.panelBorderMuted
                          : AppTheme.accentGreen.withValues(alpha: 0.65),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              AppSpacing.gapS2,
              Text(
                'Valutazione manuale: sempre le tre coppie EUR/USD, GBP/USD, GBP/JPY su Capital.com '
                '(indipendente dalle quotazioni mostrate sopra).',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryText.withValues(alpha: 0.88),
                ),
              ),
              if (signalsViewModel.liveEvalEnabled) ...[
                AppSpacing.gapS2,
                Text(
                  'Valutazione automatica strategia ogni '
                  '${signalsViewModel.liveEvalIntervalMinutes} min '
                  '(stesse tre coppie).',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText.withValues(alpha: 0.88),
                  ),
                ),
              ] else ...[
                AppSpacing.gapS2,
                Text(
                  'Valutazione automatica disattivata in strategia; il pulsante manuale resta disponibile.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText.withValues(alpha: 0.88),
                  ),
                ),
              ],
              if (signalsViewModel.capitalEvalError != null) ...[
                AppSpacing.gapS2,
                Text(
                  signalsViewModel.capitalEvalError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.accentRed.withValues(alpha: 0.92),
                  ),
                ),
              ],
              if (signalsViewModel.lastCapitalEvalSummary != null) ...[
                AppSpacing.gapS2,
                Text(
                  signalsViewModel.lastCapitalEvalSummary!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText.withValues(alpha: 0.95),
                  ),
                ),
              ],

              AppSpacing.gapSectionLg,

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: NeonSectionTitle('SEGNALI ATTIVI'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.inputFillColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.accentGreen.withValues(alpha: 0.55),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      signalsViewModel.isLoading
                          ? '…'
                          : signalsViewModel.activeSignalCount.toString(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentGreen,
                        height: 1,
                        shadows: AppTheme.neonTextGlow(
                          blurInner: 8,
                          blurOuter: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapSection,

              if (signalsViewModel.isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: CircularProgressIndicator(
                      color: AppTheme.accentGreen,
                    ),
                  ),
                )
              else if (active.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: Text(
                      'Nessun segnale attivo al momento',
                      style: TextStyle(
                        color: AppTheme.secondaryText.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: active.map((signal) {
                    final epic = normalizedPairEpic(signal.pair);
                    QuoteModel? quote;
                    for (final q in marketProvider.liveQuotes) {
                      if (normalizedPairEpic(q.epic) == epic) {
                        quote = q;
                        break;
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                      child: SignalHistoryItem(
                        signal: signal,
                        liveQuote: quote,
                        onTap: null,
                        onEditRealSignal: () => showRealSignalEditBottomSheet(
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
                              context
                                  .read<SignalsViewModel>()
                                  .submitLiveSignalEdits(
                                    signal,
                                    entryPrice: entryPrice,
                                    stopLoss: stopLoss,
                                    executionConfirmed: executionConfirmed,
                                    clearExit: clearExit,
                                    exitPrice: exitPrice,
                                    exitTime: exitTime,
                                  ),
                        ),
                        onShowIndicators: () =>
                            showSignalDetailBottomSheet(context, signal),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go(AppRouter.testRoute);
              break;
            case 1:
              context.go(AppRouter.reportRoute);
              break;
            case 2:
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
}
