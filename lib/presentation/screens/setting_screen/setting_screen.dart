import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../data/repositories/strategy_config_repository.dart';
import '../../../data/repositories/strategy_config_repository_impl.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_bottom_nav_bar.dart';
import '../../widgets/custom_button.dart';
import 'filters_view_model.dart';
import 'indicators_view_model.dart';
import 'risk_view_model.dart';
import 'setting_view_model.dart';
import 'timeframe_view_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/routing/app_router.dart';
import 'widgets/indicator_setting_card.dart';
import 'widgets/risk_general_parameters_card.dart';
import 'widgets/risk_sl_tp_atr_card.dart';
import 'widgets/risk_protection_cards.dart';
import 'widgets/neon_settings_controls.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomAuthProvider>(
          create: (_) => CustomAuthProvider(),
        ),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(),
        ),
        Provider<StrategyConfigRepository>(
          create: (_) => StrategyConfigRepositoryImpl(),
        ),
        ChangeNotifierProvider<IndicatorsViewModel>(
          create: (context) => IndicatorsViewModel(
            context.read<CustomAuthProvider>(),
            context.read<StrategyConfigRepository>(),
          ),
        ),
        ChangeNotifierProvider<FiltersViewModel>(
          create: (context) => FiltersViewModel(
            context.read<CustomAuthProvider>(),
            context.read<StrategyConfigRepository>(),
          ),
        ),
        ChangeNotifierProvider<RiskViewModel>(
          create: (context) => RiskViewModel(
            context.read<CustomAuthProvider>(),
            context.read<StrategyConfigRepository>(),
          ),
        ),
        ChangeNotifierProvider<TimeframeViewModel>(
          create: (context) => TimeframeViewModel(
            context.read<CustomAuthProvider>(),
            context.read<StrategyConfigRepository>(),
          ),
        ),
      ],
      child: const SettingsView(),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: AppTheme.backgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'IMPOSTAZIONI',
            style: TextStyle(
              color: AppTheme.accentGreen,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: 2.2,
              shadows: AppTheme.neonTextGlow(),
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.accentGreen,
            unselectedLabelColor:
                AppTheme.secondaryText.withValues(alpha: 0.88),
            indicatorColor: AppTheme.accentGreen,
            indicatorWeight: 2.5,
            dividerColor: AppTheme.panelBorderMuted.withValues(alpha: 0.6),
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            tabs: const [
              Tab(text: 'Credenziali'),
              Tab(text: 'Timeframe'),
              Tab(text: 'Indicatori'),
              Tab(text: 'Filtri'),
              Tab(text: 'Risk'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CredenzialiTab(),
            TimeframeTab(),
            IndicatoriTab(),
            FiltriTab(),
            RiskTab(),
          ],
        ),
        bottomNavigationBar: CustomBottomNavBar(
          currentIndex: 4,
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
                context.go(AppRouter.historyRoute);
                break;
              case 4:
                break;
            }
          },
        ),
      ),
    );
  }
}

// ========== CREDENZIALI TAB ==========
class CredenzialiTab extends StatelessWidget {
  const CredenzialiTab({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SettingsViewModel>();
    final isLoading = viewModel.isLoading;

    return SingleChildScrollView(
      padding: AppSpacing.card,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: kNeonSettingsInputDecorationTheme,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          NeonSettingsCardTitleRow(
            title: 'Collega Capital.com',
            leadingIcon: Icons.link_rounded,
          ),
          AppSpacing.gapS2,
          const Text(
            'Le credenziali vengono salvate in modo sicuro e crittografato.',
            style: TextStyle(color: AppTheme.secondaryText),
          ),
          AppSpacing.gapSectionLg,
          NeonSettingsControllerField(
            label: 'API KEY',
            controller: viewModel.apiKeyController,
            obscureText: viewModel.obscureApiKey,
            trailing: IconButton(
              icon: Icon(
                viewModel.obscureApiKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.accentGreen,
              ),
              onPressed: viewModel.toggleObscureApiKey,
            ),
          ),
          AppSpacing.gapSection,
          NeonSettingsControllerField(
            label: 'LOGIN',
            controller: viewModel.loginController,
          ),
          AppSpacing.gapSection,
          NeonSettingsControllerField(
            label: 'PASSWORD',
            controller: viewModel.passwordController,
            obscureText: viewModel.obscurePassword,
            trailing: IconButton(
              icon: Icon(
                viewModel.obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.accentGreen,
              ),
              onPressed: viewModel.toggleObscurePassword,
            ),
          ),
          AppSpacing.gapS6,
          if (viewModel.status == SettingsStatus.success &&
              viewModel.successMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.section),
              child: Text(
                viewModel.successMessage,
                style: const TextStyle(color: AppTheme.accentGreen),
              ),
            ),
          if (viewModel.status == SettingsStatus.error &&
              viewModel.errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.section),
              child: Text(
                viewModel.errorMessage,
                style: const TextStyle(color: AppTheme.accentRed),
              ),
            ),
          CustomButton(
            text: 'SALVA',
            onPressed: isLoading
                ? null
                : () => viewModel.saveCredentials(
                    viewModel.apiKeyController.text,
                    viewModel.loginController.text,
                    viewModel.passwordController.text,
                  ),
            isLoading: isLoading,
          ),
          AppSpacing.gapSection,
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: isLoading
                ? null
                : () async {
                    await viewModel.deleteCredentials();
                  },
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Cancella credenziali'),
          ),
        ],
        ),
      ),
    );
  }
}

// ========== TIMEFRAME TAB ==========
class TimeframeTab extends StatelessWidget {
  const TimeframeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TimeframeViewModel>();
    if (vm.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final config = vm.config;
    return SingleChildScrollView(
      padding: AppSpacing.card,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: kNeonSettingsInputDecorationTheme,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          NeonSettingsCardTitleRow(
            title: 'Timeframe',
            leadingIcon: Icons.schedule_rounded,
          ),
          AppSpacing.gapSection,
          NeonSettingsDropdownField<String>(
            label: 'Timeframe operativo',
            value: config?.timeframes.operativo ?? '15m',
            items: const [
              DropdownMenuItem(value: '10m', child: Text('10 minuti')),
              DropdownMenuItem(value: '15m', child: Text('15 minuti')),
              DropdownMenuItem(value: '30m', child: Text('30 minuti')),
            ],
            onChanged: (value) {
              if (value != null) vm.updateOperativo(value);
            },
          ),
          AppSpacing.gapSection,
          NeonSettingsDropdownField<String>(
            label: 'Timeframe medio',
            value: config?.timeframes.medio ?? '4h',
            items: const [
              DropdownMenuItem(value: '1h', child: Text('1 ora')),
              DropdownMenuItem(value: '4h', child: Text('4 ore')),
            ],
            onChanged: (value) {
              if (value != null) vm.updateMedio(value);
            },
          ),
          AppSpacing.gapSection,
          NeonSettingsDropdownField<String>(
            label: 'Timeframe lungo',
            value: config?.timeframes.lungo ?? '1d',
            items: const [
              DropdownMenuItem(value: '1d', child: Text('1 giorno')),
              DropdownMenuItem(value: '1w', child: Text('1 settimana')),
            ],
            onChanged: (value) {
              if (value != null) vm.updateLungo(value);
            },
          ),
          AppSpacing.gapSection,
          NeonSettingsDropdownField<String>(
            label: 'Timeframe test',
            value: config?.timeframes.test ?? '1m',
            items: const [
              DropdownMenuItem(value: 'tick', child: Text('Tick')),
              DropdownMenuItem(value: '1m', child: Text('1 minuto')),
            ],
            onChanged: (value) {
              if (value != null) vm.updateTest(value);
            },
          ),
          AppSpacing.gapS6,
          ElevatedButton(
            onPressed: () async {
              await vm.save();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Timeframe salvati con successo')),
              );
            },
            child: const Text('Salva Timeframe'),
          ),
        ],
        ),
      ),
    );
  }
}

// ========== INDICATORI TAB ==========
class IndicatoriTab extends StatelessWidget {
  const IndicatoriTab({super.key});

  @override
  Widget build(BuildContext context) {
    final indicatorsVM = context.watch<IndicatorsViewModel>();
    if (indicatorsVM.config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final config = indicatorsVM.config!;
    final ind = config.indicators;

    return SingleChildScrollView(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IndicatorSettingCard(
            title: 'EMA Lunga',
            enabled: ind.emaLong.enabled,
            onEnabledChanged: indicatorsVM.updateEmaLongEnabled,
            timeframeValue: ind.emaLong.timeframe,
            onTimeframeChanged: indicatorsVM.updateEmaLongTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Length',
                      value: ind.emaLong.length,
                      onChanged: indicatorsVM.updateEmaLongLength,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.emaLong.weight,
                      onChanged: indicatorsVM.updateEmaLongWeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'EMA Corta',
            enabled: ind.emaShort.enabled,
            onEnabledChanged: indicatorsVM.updateEmaShortEnabled,
            timeframeValue: ind.emaShort.timeframe,
            onTimeframeChanged: indicatorsVM.updateEmaShortTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Length',
                      value: ind.emaShort.length,
                      onChanged: indicatorsVM.updateEmaShortLength,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.emaShort.weight,
                      onChanged: indicatorsVM.updateEmaShortWeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'RSI',
            leadingIcon: Icons.speed_rounded,
            enabled: ind.rsi.enabled,
            onEnabledChanged: indicatorsVM.updateRsiEnabled,
            timeframeValue: ind.rsi.timeframe,
            onTimeframeChanged: indicatorsVM.updateRsiTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Length',
                      value: ind.rsi.length,
                      onChanged: indicatorsVM.updateRsiLength,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.rsi.weight,
                      onChanged: indicatorsVM.updateRsiWeight,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapS2,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Oversold',
                      value: ind.rsi.oversold,
                      min: 0,
                      max: 100,
                      onChanged: indicatorsVM.updateRsiOversold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Overbought',
                      value: ind.rsi.overbought,
                      min: 0,
                      max: 100,
                      onChanged: indicatorsVM.updateRsiOverbought,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'MACD',
            leadingIcon: Icons.multiline_chart_rounded,
            enabled: ind.macd.enabled,
            onEnabledChanged: indicatorsVM.updateMacdEnabled,
            timeframeValue: ind.macd.timeframe,
            onTimeframeChanged: indicatorsVM.updateMacdTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Fast',
                      value: ind.macd.fast,
                      onChanged: indicatorsVM.updateMacdFast,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Slow',
                      value: ind.macd.slow,
                      onChanged: indicatorsVM.updateMacdSlow,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapS2,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Signal',
                      value: ind.macd.signal,
                      onChanged: indicatorsVM.updateMacdSignal,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.macd.weight,
                      onChanged: indicatorsVM.updateMacdWeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'SMA Signal',
            leadingIcon: Icons.timeline_rounded,
            enabled: ind.smaSignal.enabled,
            onEnabledChanged: indicatorsVM.updateSmaSignalEnabled,
            timeframeValue: ind.smaSignal.timeframe,
            onTimeframeChanged: indicatorsVM.updateSmaSignalTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Length',
                      value: ind.smaSignal.length,
                      onChanged: indicatorsVM.updateSmaSignalLength,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.smaSignal.weight,
                      onChanged: indicatorsVM.updateSmaSignalWeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'Pivot',
            leadingIcon: Icons.pivot_table_chart_rounded,
            enabled: ind.pivot.enabled,
            onEnabledChanged: indicatorsVM.updatePivotEnabled,
            timeframeValue: ind.pivot.timeframe,
            onTimeframeChanged: indicatorsVM.updatePivotTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.pivot.weight,
                      onChanged: indicatorsVM.updatePivotWeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'ADR Score',
            leadingIcon: Icons.area_chart_rounded,
            enabled: ind.adrScore.enabled,
            onEnabledChanged: indicatorsVM.updateAdrScoreEnabled,
            timeframeValue: ind.adrScore.timeframe,
            onTimeframeChanged: indicatorsVM.updateAdrScoreTimeframe,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Length',
                      value: ind.adrScore.length,
                      onChanged: indicatorsVM.updateAdrScoreLength,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Weight',
                      value: ind.adrScore.weight,
                      onChanged: indicatorsVM.updateAdrScoreWeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapSection,
          ElevatedButton(
            onPressed: () async {
              await indicatorsVM.save();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Indicatori salvati con successo'),
                ),
              );
            },
            child: const Text('Salva Indicatori'),
          ),
        ],
      ),
    );
  }
}

// ========== FILTRI TAB ==========
class FiltriTab extends StatelessWidget {
  const FiltriTab({super.key});

  @override
  Widget build(BuildContext context) {
    final filtersVM = context.watch<FiltersViewModel>();
    if (filtersVM.config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final config = filtersVM.config!;
    final f = config.filters;
    final ts = f.tradingSession;

    return SingleChildScrollView(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IndicatorSettingCard(
            title: 'SuperTrend',
            leadingIcon: Icons.trending_up_rounded,
            enabled: f.superTrend.enabled,
            onEnabledChanged: filtersVM.updateSuperTrendEnabled,
            timeframeValue: f.superTrend.timeframe,
            onTimeframeChanged: filtersVM.updateSuperTrendTimeframe,
            showTimeframeLabel: true,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NeonMetricIntCell(
                      label: 'Period',
                      value: f.superTrend.period,
                      min: 1,
                      max: 500,
                      onChanged: filtersVM.updateSuperTrendPeriod,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapS2,
              NeonSliderTile(
                label: 'Multiplier',
                value: f.superTrend.multiplier,
                onChanged: filtersVM.updateSuperTrendMultiplier,
                min: 1.0,
                max: 5.0,
                divisions: 80,
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'Bollinger',
            leadingIcon: Icons.candlestick_chart_rounded,
            enabled: f.bollinger.enabled,
            onEnabledChanged: filtersVM.updateBollingerEnabled,
            timeframeValue: f.bollinger.timeframe,
            onTimeframeChanged: filtersVM.updateBollingerTimeframe,
            showTimeframeLabel: true,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: NeonMetricIntCell(
                      label: 'Length',
                      value: f.bollinger.length,
                      min: 1,
                      max: 500,
                      onChanged: filtersVM.updateBollingerLength,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    flex: 7,
                    child: NeonSliderTile(
                      label: 'Std dev',
                      value: f.bollinger.std,
                      onChanged: filtersVM.updateBollingerStd,
                      min: 1.0,
                      max: 3.0,
                      divisions: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IndicatorSettingCard(
            title: 'ADX',
            leadingIcon: Icons.analytics_rounded,
            enabled: f.adx.enabled,
            onEnabledChanged: filtersVM.updateAdxEnabled,
            timeframeValue: f.adx.timeframe,
            onTimeframeChanged: filtersVM.updateAdxTimeframe,
            showTimeframeLabel: true,
            parameterRows: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: NeonMetricIntCell(
                      label: 'Period',
                      value: f.adx.period,
                      min: 1,
                      max: 200,
                      onChanged: filtersVM.updateAdxPeriod,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    flex: 7,
                    child: NeonSliderTile(
                      label: 'Threshold',
                      value: f.adx.threshold,
                      onChanged: filtersVM.updateAdxThreshold,
                      min: 10,
                      max: 50,
                      divisions: 80,
                      fractionDigits: 0,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapS2,
              NeonLabeledSwitchTile(
                label: 'Filter DI (con ADX)',
                value: f.adx.filterDi,
                onChanged: filtersVM.updateAdxFilterDi,
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s1),
                child: Text(
                  'Se attivo: sul timeframe ADX, i long richiedono +DI > −DI e gli short −DI > +DI (Wilder, stesso periodo).',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppTheme.secondaryText.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
          NeonSettingsPanel(
            title: 'Volatilità e ADR',
            titleIcon: Icons.area_chart_rounded,
            children: [
              NeonSliderTile(
                label: 'Max ADR extension',
                value: f.maxAdrExtension,
                onChanged: filtersVM.updateMaxAdrExtension,
                min: 0.5,
                max: 1.5,
                divisions: 50,
              ),
              NeonSliderTile(
                label: 'Min ATR level',
                value: f.minAtrLevel,
                onChanged: filtersVM.updateMinAtrLevel,
                min: 0.0001,
                max: 0.002,
                divisions: null,
                fractionDigits: 5,
              ),
            ],
          ),
          NeonSettingsPanel(
            title: 'Sessione di trading',
            titleIcon: Icons.schedule_rounded,
            children: [
              NeonLabeledSwitchTile(
                label: 'Sessione attiva',
                value: ts.enabled,
                onChanged: filtersVM.updateTradingSessionEnabled,
              ),
              Opacity(
                opacity: ts.enabled ? 1.0 : 0.42,
                child: IgnorePointer(
                  ignoring: !ts.enabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NeonCompactTextField(
                        label: 'Inizio (HH:MM)',
                        initialValue: ts.start,
                        onChanged: filtersVM.updateTradingSessionStart,
                      ),
                      AppSpacing.gapS2,
                      NeonCompactTextField(
                        label: 'Fine (HH:MM)',
                        initialValue: ts.end,
                        onChanged: filtersVM.updateTradingSessionEnd,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          NeonSettingsPanel(
            title: 'Spread',
            titleIcon: Icons.compare_arrows_rounded,
            children: [
              NeonSliderTile(
                label: 'Max spread (pips)',
                value: f.maxSpreadAllowed,
                onChanged: filtersVM.updateMaxSpreadAllowed,
                min: 0,
                max: 10,
                divisions: 100,
                fractionDigits: 1,
              ),
            ],
          ),
          AppSpacing.gapSection,
          ElevatedButton(
            onPressed: () async {
              await filtersVM.save();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Filtri salvati con successo')),
              );
            },
            child: const Text('Salva Filtri'),
          ),
        ],
      ),
    );
  }
}

// ========== RISK TAB ==========
class RiskTab extends StatelessWidget {
  const RiskTab({super.key});

  @override
  Widget build(BuildContext context) {
    final riskVM = context.watch<RiskViewModel>();
    if (riskVM.config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final config = riskVM.config!;

    return SingleChildScrollView(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiskGeneralParametersCard(
            maxSimultaneousTrades: config.exitRules.maxSimultaneousTrades,
            onMaxSimultaneousTradesChanged: riskVM.updateMaxSimultaneousTrades,
            activationScore: config.exitRules.activationScore,
            onActivationScoreChanged: riskVM.updateActivationScore,
            minLotPerTrade: config.exitRules.minLotPerTrade,
            onMinLotPerTradeChanged: riskVM.updateMinLotPerTrade,
            initialCapitalEuro: config.initialCapitalEuro,
            onInitialCapitalEuroChanged: riskVM.updateInitialCapitalEuro,
          ),
          RiskSlTpAtrCard(
            slAtrMult: config.exitRules.slAtrMult,
            tpAtrMult: config.exitRules.tpAtrMult,
            onSlChanged: riskVM.updateSlAtrMult,
            onTpChanged: riskVM.updateTpAtrMult,
          ),
          RiskBreakEvenCard(
            active: config.exitRules.breakEven.active,
            onActiveChanged: riskVM.updateBreakEvenActive,
            triggerAtrMult: config.exitRules.breakEven.triggerAtrMult,
            onTriggerChanged: riskVM.updateBreakEvenTriggerAtrMult,
            lockAtrMult: config.exitRules.breakEven.lockAtrMult,
            onLockChanged: riskVM.updateBreakEvenLockAtrMult,
          ),
          RiskTrailingStopCard(
            active: config.exitRules.trailingStop.active,
            onActiveChanged: riskVM.updateTrailingStopActive,
            activationAtrMult: config.exitRules.trailingStop.activationAtrMult,
            onActivationChanged: riskVM.updateTrailingStopActivationAtrMult,
            stepAtrMult: config.exitRules.trailingStop.stepAtrMult,
            onStepChanged: riskVM.updateTrailingStopStepAtrMult,
          ),
          AppSpacing.gapSection,
          ElevatedButton(
            onPressed: () async {
              await riskVM.save();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Risk salvati con successo')),
              );
            },
            child: const Text('Salva Risk'),
          ),
          AppSpacing.gapSection,
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await context.read<IndicatorsViewModel>().resetToDefault();
              await context.read<FiltersViewModel>().resetToDefault();
              await context.read<RiskViewModel>().resetToDefault();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tutte le impostazioni ripristinate'),
                ),
              );
            },
            child: const Text('Ripristina tutte le impostazioni'),
          ),
        ],
      ),
    );
  }
}
