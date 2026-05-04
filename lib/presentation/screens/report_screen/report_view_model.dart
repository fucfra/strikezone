import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:strikezone/core/config/firebase_clients.dart';
import '../../../core/format/duration_format.dart';
import '../../../data/models/signal_model.dart';

enum ReportFilterType { all, real, test }

/// Coppie disponibili nel filtro report (codice EPIC come in Firestore).
const List<String> kReportFilterEpics = ['EURUSD', 'GBPUSD', 'GBPJPY'];

/// Messaggio se si tenta di deselezionare l’ultima coppia (report e storico).
const String kPairFilterAtLeastOneMessage =
    'È necessario avere almeno una coppia valutaria selezionata per visualizzare i dati.';

bool _selectedEpicsCoversAllPairs(Set<String> selected) {
  if (selected.length < kReportFilterEpics.length) return false;
  return kReportFilterEpics.every((e) => selected.contains(e.toUpperCase()));
}

/// Punto mensile per grafici report (UTC, primo del mese).
class ReportMonthlyPoint {
  final DateTime monthUtc;
  final double netPnlEuro;
  final double equityEndEuro;

  const ReportMonthlyPoint({
    required this.monthUtc,
    required this.netPnlEuro,
    required this.equityEndEuro,
  });
}

/// Conteggi giornalieri (UTC, mezzanotte del giorno) per grafico aperture/chiusure.
class ReportDailyOpenClosePoint {
  /// Inizio giorno UTC (00:00).
  final DateTime dayUtc;
  final int opens;
  final int closes;

  const ReportDailyOpenClosePoint({
    required this.dayUtc,
    required this.opens,
    required this.closes,
  });
}

/// Estremo P&L netto (dopo spread) su un singolo trade, per box report.
class ReportNetPnlExtreme {
  final double netPnlEuro;
  final double signalScore;
  final DateTime referenceDateUtc;
  final String pairEpic;
  final String? quoteCurrency;

  const ReportNetPnlExtreme({
    required this.netPnlEuro,
    required this.signalScore,
    required this.referenceDateUtc,
    required this.pairEpic,
    this.quoteCurrency,
  });
}

class ReportViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  String? _userId;
  List<SignalModel> _signals = [];
  bool _isLoading = false;
  String? _error;
  double _initialCapitalEuro = 10000.0;

  /// Default "Reali": alla prima apertura mostra solo i segnali live.
  ReportFilterType _typeFilter = ReportFilterType.real;
  /// Sottoinsieme di [kReportFilterEpics]; se contiene tutte le EPIC → nessun filtro (tutte le coppie).
  /// Default: tutte e tre evidenziate in UI.
  Set<String> _selectedEpics = Set<String>.from(kReportFilterEpics);
  DateTime? _startDate;
  DateTime? _endDate;
  StreamSubscription<User?>? _authSub;
  bool _disposed = false;

  ReportViewModel() : _firestore = FirebaseClients.firestore() {
    _userId = FirebaseAuth.instance.currentUser?.uid;
    if (_userId != null) {
      _loadSignals();
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_disposed) return;
      _userId = user?.uid;
      if (_userId != null) {
        _loadSignals();
      } else {
        _signals = [];
        if (!_disposed) notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _authSub = null;
    super.dispose();
  }

  List<SignalModel> get signals => _signals;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ReportFilterType get typeFilter => _typeFilter;
  /// Copia immutabile degli EPIC selezionati (tutte le chiavi in [kReportFilterEpics] ⇒ coorte completa).
  Set<String> get selectedEpics => Set.unmodifiable(_selectedEpics);

  /// Etichetta leggibile per chip e riepilogo.
  static String formatEpicLabel(String epic) {
    final u = epic.toUpperCase();
    switch (u) {
      case 'EURUSD':
        return 'EUR/USD';
      case 'GBPUSD':
        return 'GBP/USD';
      case 'GBPJPY':
        return 'GBP/JPY';
      default:
        if (u.length >= 6) {
          return '${u.substring(0, 3)}/${u.substring(3)}';
        }
        return u;
    }
  }

  /// Testo riepilogo sotto i chip (una riga, compatto).
  String get pairsSelectionSummary {
    if (_selectedEpicsCoversAllPairs(_selectedEpics)) {
      return 'Tutte le coppie (${kReportFilterEpics.length})';
    }
    final sorted = _selectedEpics.toList()..sort();
    return sorted.map(formatEpicLabel).join(' · ');
  }

  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  double get initialCapitalEuro => _initialCapitalEuro;

  double _calculatePips(SignalModel signal) {
    return signal.effectivePips ?? 0.0;
  }

  /// Segnali da includere in Σ pips, Σ EUR, spread, win rate: test da backtest oppure
  /// reali che hanno entrambi i campi salvati dal motore di simulazione (evita pips
  /// ricalcolati da entry/exit che non coincidono col log di run_backtest).
  List<SignalModel> get _signalsForMetricsAggregation {
    return _signals.where((s) {
      if (s.isTest) return true;
      return s.realizedPips != null && s.realizedPnlEuro != null;
    }).toList();
  }

  int get metricsTradeCount => _signalsForMetricsAggregation.length;

  int get totalStopLossAdjustments => _signalsForMetricsAggregation.fold(
        0,
        (acc, s) => acc + s.stopLossAdjustmentCount,
      );

  double get avgStopLossAdjustmentsPerSignal =>
      metricsTradeCount > 0
          ? totalStopLossAdjustments / metricsTradeCount
          : 0.0;

  int get maxStopLossAdjustmentsOnSignal {
    final agg = _signalsForMetricsAggregation;
    if (agg.isEmpty) return 0;
    var m = 0;
    for (final s in agg) {
      if (s.stopLossAdjustmentCount > m) m = s.stopLossAdjustmentCount;
    }
    return m;
  }

  String get avgStopLossAdjustmentsDisplay =>
      metricsTradeCount > 0 ? avgStopLossAdjustmentsPerSignal.toStringAsFixed(2) : '—';

  /// Vittorie per TP (stessa coorte del WIN RATE: pips > 0, `exit_reason` TP).
  int get metricsWinProfitTakeProfitCount => _signalsForMetricsAggregation
      .where(
        (s) =>
            _normalizedExitReason(s) == 'TP' && _calculatePips(s) > 0,
      )
      .length;

  /// Vittorie chiuse in utile dopo BE/trailing (`SL_BE` / `SL_TRAIL`, pips > 0).
  int get metricsWinProfitBreakEvenOrTrailingCount =>
      _signalsForMetricsAggregation.where((s) {
        final e = _normalizedExitReason(s);
        return (e == 'SL_BE' || e == 'SL_TRAIL') && _calculatePips(s) > 0;
      }).length;

  /// Perdite per uscita su stop (SL iniziale o SL dopo BE/trailing), pips < 0.
  int get metricsLossStopLossHitCount => _signalsForMetricsAggregation.where((s) {
        final e = _normalizedExitReason(s);
        if (e != 'SL' && e != 'SL_BE' && e != 'SL_TRAIL') return false;
        return _calculatePips(s) < 0;
      }).length;

  /// Segnali in coorte metriche non ricadenti nei tre bucket (es. `no_exit`, pips nulli).
  int get metricsDistributionOtherCount {
    final a = metricsWinProfitTakeProfitCount;
    final b = metricsWinProfitBreakEvenOrTrailingCount;
    final c = metricsLossStopLossHitCount;
    return metricsTradeCount - a - b - c;
  }

  String? get aggregationNote {
    final v = _signals.length;
    final m = metricsTradeCount;
    if (m == v) return null;
    if (m == 0) {
      return 'Nessun segnale con metriche di simulazione nel filtro attuale. '
          'Per i risultati del backtest scegli tipo "Test".';
    }
    return 'Pips, P&L EUR e spread sono sommati su $m di $v segnali '
        '(esclusi i reali senza realized_pips e realized_pnl_eur).';
  }

  void setTypeFilter(ReportFilterType filter) {
    _typeFilter = filter;
    _loadSignals();
  }

  /// Imposta l’insieme di EPIC (intersezione con [kReportFilterEpics]). Se contiene tutte, restano tutte selezionate in UI.
  void setSelectedEpics(Set<String> epics) {
    final cleaned = epics
        .map((e) => e.toUpperCase())
        .where((e) => kReportFilterEpics.contains(e))
        .toSet();
    if (cleaned.isEmpty || cleaned.length >= kReportFilterEpics.length) {
      _selectedEpics = Set<String>.from(kReportFilterEpics);
    } else {
      _selectedEpics = cleaned;
    }
    _loadSignals();
  }

  /// “Tutte le coppie” (tutti i chip in evidenza).
  void clearPairFilter() {
    _selectedEpics = Set<String>.from(kReportFilterEpics);
    _loadSignals();
  }

  /// Toggle di un EPIC nei chip. Non consente zero coppie: ritorna [kPairFilterAtLeastOneMessage] in quel caso.
  /// Con tutte e tre attive, aggiungendo l’ultima mancante si resta con tutte evidenziate.
  String? toggleEpicFilter(String epic) {
    final e = epic.toUpperCase();
    if (!kReportFilterEpics.contains(e)) return null;
    var next = Set<String>.from(_selectedEpics);
    if (next.contains(e)) {
      if (next.length == 1) {
        return kPairFilterAtLeastOneMessage;
      }
      next.remove(e);
    } else {
      next.add(e);
      if (next.length >= kReportFilterEpics.length) {
        next = Set<String>.from(kReportFilterEpics);
      }
    }
    _selectedEpics = next;
    _loadSignals();
    return null;
  }

  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    _loadSignals();
  }

  void clearDateRange() {
    _startDate = null;
    _endDate = null;
    _loadSignals();
  }

  Future<void> _loadSignals() async {
    if (_userId == null) return;
    if (_disposed) return;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      List<SignalModel> allSignals = [];

      // Carica segnali reali se richiesto
      if (_typeFilter == ReportFilterType.real ||
          _typeFilter == ReportFilterType.all) {
        final realQuery = _firestore
            .collection('signals')
            .where('userId', isEqualTo: _userId);
        final realSnapshot = await realQuery.get();
        allSignals.addAll(
          realSnapshot.docs.map((doc) => SignalModel.fromFirestore(doc)),
        );
      }

      // Carica segnali di test se richiesto
      if (_typeFilter == ReportFilterType.test ||
          _typeFilter == ReportFilterType.all) {
        final testQuery = _firestore
            .collection('test_signals')
            .where('userId', isEqualTo: _userId);
        final testSnapshot = await testQuery.get();
        allSignals.addAll(
          testSnapshot.docs.map((doc) => SignalModel.fromFirestore(doc)),
        );
      }

      // Filtra per coppia (sottoinsieme di [kReportFilterEpics]; tutte selezionate = nessun filtro)
      if (!_selectedEpicsCoversAllPairs(_selectedEpics)) {
        allSignals = allSignals
            .where((s) => _selectedEpics.contains(s.pair.toUpperCase()))
            .toList();
      }

      // Filtra per data (giorni inclusivi in UTC, come intervalli backtest su storico)
      if (_startDate != null) {
        final startDay = DateTime.utc(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        );
        allSignals = allSignals.where((s) {
          final u = s.timestamp.toUtc();
          final day = DateTime.utc(u.year, u.month, u.day);
          return !day.isBefore(startDay);
        }).toList();
      }
      if (_endDate != null) {
        final endDay = DateTime.utc(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
        );
        allSignals = allSignals.where((s) {
          final u = s.timestamp.toUtc();
          final day = DateTime.utc(u.year, u.month, u.day);
          return !day.isAfter(endDay);
        }).toList();
      }

      if (_disposed) return;
      allSignals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _signals = allSignals;

      final cfgSnap = await _firestore
          .collection('strategy_configs')
          .doc(_userId!)
          .get();
      if (!_disposed) {
        if (cfgSnap.exists) {
          final d = cfgSnap.data();
          _initialCapitalEuro =
              (d?['initialCapitalEuro'] as num?)?.toDouble() ?? 10000.0;
        } else {
          _initialCapitalEuro = 10000.0;
        }
      }
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
      }
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Metodi per statistiche aggregate
  int get totalTrades => _signals.length;
  int get winningTrades => _signalsForMetricsAggregation
      .where((s) => _calculatePips(s) > 0)
      .length;
  int get losingTrades => _signalsForMetricsAggregation
      .where((s) => _calculatePips(s) < 0)
      .length;
  double get winRate =>
      metricsTradeCount > 0 ? winningTrades / metricsTradeCount : 0.0;
  double get totalPips => _signalsForMetricsAggregation.fold(
        0.0,
        (sum, s) => sum + _calculatePips(s),
      );
  double get avgPipsPerTrade =>
      metricsTradeCount > 0 ? totalPips / metricsTradeCount : 0.0;
  /// Somma P&L in EUR (solo segnali con metriche di simulazione aggregate).
  double get totalPnlEuro => _signalsForMetricsAggregation.fold(
        0.0,
        (sum, s) => sum + (s.realizedPnlEuro ?? 0.0),
      );

  /// P&L al netto dello spread (per trade), come nel grafico mensile.
  static double netPnlEuroForTrade(SignalModel s) {
    final pnl = s.realizedPnlEuro ?? 0.0;
    final spr = s.spreadPaidEuro ?? 0.0;
    return pnl - spr;
  }

  double get totalNetPnlEuroAfterSpread => _signalsForMetricsAggregation.fold(
        0.0,
        (sum, s) => sum + netPnlEuroForTrade(s),
      );

  ReportNetPnlExtreme? get largestNetGainExtreme {
    final agg = _signalsForMetricsAggregation;
    if (agg.isEmpty) return null;
    SignalModel? best;
    var bestNet = double.negativeInfinity;
    for (final s in agg) {
      final n = netPnlEuroForTrade(s);
      if (n > bestNet) {
        bestNet = n;
        best = s;
      }
    }
    if (best == null || !bestNet.isFinite) return null;
    final exitOrOpen = best.exitTime ?? best.timestamp;
    return ReportNetPnlExtreme(
      netPnlEuro: bestNet,
      signalScore: best.score,
      referenceDateUtc: exitOrOpen.toUtc(),
      pairEpic: best.pair,
      quoteCurrency: best.quoteCurrency,
    );
  }

  ReportNetPnlExtreme? get largestNetLossExtreme {
    final agg = _signalsForMetricsAggregation;
    if (agg.isEmpty) return null;
    SignalModel? worst;
    var worstNet = double.infinity;
    for (final s in agg) {
      final n = netPnlEuroForTrade(s);
      if (n < worstNet) {
        worstNet = n;
        worst = s;
      }
    }
    if (worst == null || !worstNet.isFinite) return null;
    final exitOrOpen = worst.exitTime ?? worst.timestamp;
    return ReportNetPnlExtreme(
      netPnlEuro: worstNet,
      signalScore: worst.score,
      referenceDateUtc: exitOrOpen.toUtc(),
      pairEpic: worst.pair,
      quoteCurrency: worst.quoteCurrency,
    );
  }

  /// Mesi con almeno un trade aggregabile, ordinati cronologicamente.
  List<ReportMonthlyPoint> get monthlyReportPoints {
    final trades = List<SignalModel>.from(_signalsForMetricsAggregation);
    trades.sort((a, b) {
      final ta = a.exitTime ?? a.timestamp;
      final tb = b.exitTime ?? b.timestamp;
      return ta.compareTo(tb);
    });
    final monthNet = <String, double>{};
    for (final s in trades) {
      final d = (s.exitTime ?? s.timestamp).toUtc();
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}';
      monthNet[key] =
          (monthNet[key] ?? 0.0) + netPnlEuroForTrade(s);
    }
    final keys = monthNet.keys.toList()..sort();
    var eq = _initialCapitalEuro;
    final out = <ReportMonthlyPoint>[];
    for (final k in keys) {
      final y = int.parse(k.substring(0, 4));
      final m = int.parse(k.substring(5, 7));
      final net = monthNet[k]!;
      eq += net;
      out.add(ReportMonthlyPoint(
        monthUtc: DateTime.utc(y, m, 1),
        netPnlEuro: net,
        equityEndEuro: eq,
      ));
    }
    return out;
  }

  double get endingEquityEuro {
    final pts = monthlyReportPoints;
    if (pts.isEmpty) {
      return _initialCapitalEuro;
    }
    return pts.last.equityEndEuro;
  }

  /// Serie giornaliera: aperture per `timestamp` (giorno UTC), chiusure per `exitTime` (giorno UTC).
  /// Giorni senza eventi hanno 0; l’intervallo copre dal primo al ultimo giorno con almeno un evento,
  /// esteso a oggi (UTC) se restano segnali ancora aperti.
  List<ReportDailyOpenClosePoint> get dailyOpenCloseSeries {
    if (_signals.isEmpty) return [];

    final Map<String, List<int>> keyToCounts = {};
    void addCount(String key, {bool open = false, bool close = false}) {
      final e = keyToCounts.putIfAbsent(key, () => [0, 0]);
      if (open) e[0]++;
      if (close) e[1]++;
    }

    DateTime? minDay;
    DateTime? maxDay;

    void considerDay(DateTime d) {
      final day = _utcDateOnly(d);
      minDay = minDay == null || day.isBefore(minDay!) ? day : minDay;
      maxDay = maxDay == null || day.isAfter(maxDay!) ? day : maxDay;
    }

    for (final s in _signals) {
      final openDay = _utcDateOnly(s.timestamp.toUtc());
      considerDay(openDay);
      addCount(_dayKey(openDay), open: true);
      if (s.exitTime != null) {
        final closeDay = _utcDateOnly(s.exitTime!.toUtc());
        considerDay(closeDay);
        addCount(_dayKey(closeDay), close: true);
      }
    }

    if (minDay == null || maxDay == null) return [];

    final today = _utcDateOnly(DateTime.now().toUtc());
    var rangeEnd = maxDay!;
    if (_signals.any((s) => !s.isClosed) && today.isAfter(rangeEnd)) {
      rangeEnd = today;
    }

    final out = <ReportDailyOpenClosePoint>[];
    var cursor = minDay!;
    while (!cursor.isAfter(rangeEnd)) {
      final k = _dayKey(cursor);
      final c = keyToCounts[k] ?? const [0, 0];
      out.add(ReportDailyOpenClosePoint(dayUtc: cursor, opens: c[0], closes: c[1]));
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  static String _dayKey(DateTime dayUtc) =>
      '${dayUtc.year}-${dayUtc.month.toString().padLeft(2, '0')}-${dayUtc.day.toString().padLeft(2, '0')}';

  /// Variazione % del saldo stimato rispetto al capitale iniziale; `null` se capitale ≤ 0.
  double? get returnPercentVsInitialCapital {
    if (_initialCapitalEuro <= 0) return null;
    return (endingEquityEuro - _initialCapitalEuro) /
        _initialCapitalEuro *
        100.0;
  }

  double get totalSpreadRoundTripPips => _signalsForMetricsAggregation.fold(
        0.0,
        (a, s) => a + (s.spreadRoundTripPips ?? 0.0),
      );

  double get totalSpreadPaidEuro => _signalsForMetricsAggregation.fold(
        0.0,
        (a, s) => a + (s.spreadPaidEuro ?? 0.0),
      );
  static String? _normalizedExitReason(SignalModel s) {
    final r = s.exitReason?.trim();
    if (r == null || r.isEmpty) return null;
    return r.toUpperCase();
  }

  /// Chiusure TP: tutti i segnali nel filtro con `exit_reason` TP (non solo sottoinsieme metriche).
  int get exitCountTakeProfit => _signals
      .where((s) => _normalizedExitReason(s) == 'TP')
      .length;

  /// Stop loss iniziale (`SL`).
  int get exitCountStopLossInitial =>
      _signals.where((s) => _normalizedExitReason(s) == 'SL').length;

  /// Stop dopo break-even o trailing (`SL_BE`, `SL_TRAIL`).
  int get exitCountStopLossBreakEvenOrTrailing => _signals.where((s) {
        final e = _normalizedExitReason(s);
        return e == 'SL_BE' || e == 'SL_TRAIL';
      }).length;

  /// Segnali nel filtro senza `exit_reason` (es. reali non simulati).
  int get exitCountWithoutExitReason =>
      _signals.where((s) => _normalizedExitReason(s) == null).length;

  double get profitFactor {
    final agg = _signalsForMetricsAggregation;
    double grossProfit = agg
        .where((s) => _calculatePips(s) > 0)
        .fold(0.0, (sum, s) => sum + _calculatePips(s));
    double grossLoss = agg
        .where((s) => _calculatePips(s) < 0)
        .fold(0.0, (sum, s) => sum - _calculatePips(s));
    return grossLoss > 0
        ? grossProfit / grossLoss
        : (grossProfit > 0 ? double.infinity : 0.0);
  }

  /// Media durata apertura (solo segnali con `exitTime` e `timestamp` validi).
  String get avgOpenDurationDisplay {
    final durations = _signalsForMetricsAggregation
        .map((s) => s.openDuration)
        .whereType<Duration>()
        .where((d) => !d.isNegative)
        .toList();
    if (durations.isEmpty) return '—';
    final avgMs = durations.fold<int>(0, (a, d) => a + d.inMilliseconds) ~/
        durations.length;
    return formatDurationHuman(Duration(milliseconds: avgMs));
  }

  static DateTime _utcDateOnly(DateTime dt) {
    final u = dt.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  /// Il segnale è stato aperto per almeno un istante nel giorno UTC `[dayStart, dayStart+1)`.
  static bool _signalOpenDuringUtcCalendarDay(SignalModel s, DateTime dayStartUtc) {
    final dayEnd = dayStartUtc.add(const Duration(days: 1));
    final openStart = s.timestamp.toUtc();
    final openEnd = s.exitTime?.toUtc() ?? DateTime.now().toUtc();
    return openStart.isBefore(dayEnd) && openEnd.isAfter(dayStartUtc);
  }

  /// Primo giorno UTC incluso (filtro data o prima apertura nei segnali filtrati).
  DateTime? get _avgOpenSignalsPeriodStartUtc {
    if (_signals.isEmpty) return null;
    var d = _signals
        .map((s) => _utcDateOnly(s.timestamp.toUtc()))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (_startDate != null) {
      final u = DateTime.utc(_startDate!.year, _startDate!.month, _startDate!.day);
      if (u.isAfter(d)) d = u;
    }
    return d;
  }

  /// Ultimo giorno UTC incluso (filtro data o oggi / ultima attività nei segnali filtrati).
  DateTime? get _avgOpenSignalsPeriodEndUtc {
    if (_signals.isEmpty) return null;
    final nowDay = _utcDateOnly(DateTime.now().toUtc());
    var d = nowDay;
    for (final s in _signals) {
      final openDay = _utcDateOnly(s.timestamp.toUtc());
      if (openDay.isAfter(d)) d = openDay;
      final end = s.exitTime?.toUtc() ?? DateTime.now().toUtc();
      final endDay = _utcDateOnly(end);
      if (endDay.isAfter(d)) d = endDay;
    }
    if (_endDate != null) {
      final u = DateTime.utc(_endDate!.year, _endDate!.month, _endDate!.day);
      if (u.isBefore(d)) d = u;
    }
    return d;
  }

  /// Somma (su ogni giorno del periodo) del numero di segnali filtrati aperti in quel giorno.
  double get avgOpenSignalsPerDay {
    final start = _avgOpenSignalsPeriodStartUtc;
    final end = _avgOpenSignalsPeriodEndUtc;
    if (start == null || end == null || end.isBefore(start)) {
      return double.nan;
    }
    var sum = 0;
    var day = start;
    var nDays = 0;
    while (!day.isAfter(end)) {
      sum += _signals.where((s) => _signalOpenDuringUtcCalendarDay(s, day)).length;
      nDays++;
      day = day.add(const Duration(days: 1));
    }
    if (nDays == 0) return double.nan;
    return sum / nDays;
  }

  /// Formato italiano (virgola decimale), `—` se non calcolabile.
  String get avgOpenSignalsPerDayDisplay {
    final v = avgOpenSignalsPerDay;
    if (v.isNaN || v.isInfinite) return '—';
    return v.toStringAsFixed(2).replaceFirst('.', ',');
  }
}
