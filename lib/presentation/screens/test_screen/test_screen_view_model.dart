import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:strikezone/core/config/firebase_clients.dart';
import 'package:strikezone/core/config/firestore_dynamic_map.dart';
import 'package:strikezone/core/firebase/cloud_functions_bridge.dart';

enum TestStatus { idle, loading, success, error }

class TestViewModel extends ChangeNotifier {
  TestStatus _status = TestStatus.idle;
  String _errorMessage = '';
  String _selectedPair = 'EURUSD';
  DateTime? _startDate;
  DateTime? _endDate;

  /// Ultimo conteggio segnali da `performanceReport` (dopo test riuscito).
  int? _lastSignalCount;

  // Lista dei log di avanzamento restituiti dalla Cloud Function
  List<String> _logs = [];

  /// Sottoscrizione a `backtest_progress/{uid}` durante `run_backtest`.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _progressSub;

  /// Testo principale mostrato sotto la barra di avanzamento (da Firestore o locale).
  String? _backtestProgressTitle;

  /// Riga secondaria (es. coppia · codice stage).
  String? _backtestProgressSubtitle;

  TestViewModel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _endDate = today;
    _startDate = today.subtract(const Duration(days: 30));
  }

  TestStatus get status => _status;
  String get errorMessage => _errorMessage;
  String get selectedPair => _selectedPair;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  int? get lastSignalCount => _lastSignalCount;
  bool get isLoading => _status == TestStatus.loading;
  List<String> get logs => _logs;
  String? get backtestProgressTitle => _backtestProgressTitle;
  String? get backtestProgressSubtitle => _backtestProgressSubtitle;

  void setSelectedPair(String pair) {
    _selectedPair = pair;
    notifyListeners();
  }

  void setStartDate(DateTime? date) {
    _startDate = date;
    notifyListeners();
  }

  void setEndDate(DateTime? date) {
    _endDate = date;
    notifyListeners();
  }

  void _applyProgressSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return;
    final d = snap.data();
    if (d == null) return;
    final detail = (d['detail'] as String?)?.trim();
    final stage = (d['stage'] as String?)?.trim();
    final pair = (d['pair'] as String?)?.trim();
    _backtestProgressTitle =
        (detail != null && detail.isNotEmpty) ? detail : (stage ?? '…');
    final parts = <String>[];
    if (pair != null && pair.isNotEmpty) parts.add(pair);
    if (stage != null && stage.isNotEmpty) parts.add(stage);
    _backtestProgressSubtitle = parts.isEmpty ? null : parts.join(' · ');
    notifyListeners();
  }

  Future<void> runTest() async {
    if (_startDate == null || _endDate == null) {
      _setError('Seleziona entrambe le date');
      return;
    }
    if (_startDate!.isAfter(_endDate!)) {
      _setError('La data di inizio deve essere precedente alla fine');
      return;
    }

    _setStatus(TestStatus.loading);
    _logs.clear();
    _errorMessage = '';
    _lastSignalCount = null;
    _backtestProgressTitle = 'Connessione al server…';
    _backtestProgressSubtitle = null;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _progressSub?.cancel();
      _progressSub = FirebaseClients.firestore()
          .collection('backtest_progress')
          .doc(uid)
          .snapshots()
          .listen(_applyProgressSnapshot);
    }

    try {
      Map<String, dynamic> timeframePayload = {};
      Map<String, dynamic> indicatorsPayload = {};
      Map<String, dynamic> filtersPayload = {};
      Map<String, dynamic> exitRulesPayload = {};
      if (uid != null) {
        final doc =
            await FirebaseClients.firestore()
                .collection('strategy_configs')
                .doc(uid)
                .get();
        final data = doc.data();
        timeframePayload = stringKeyedMapFromFirestore(data?['timeframes']);
        indicatorsPayload = stringKeyedMapFromFirestore(data?['indicators']);
        filtersPayload = stringKeyedMapFromFirestore(data?['filters']);
        exitRulesPayload = stringKeyedMapFromFirestore(data?['exitRules']);
      }

      final body = await CloudFunctionsBridge.callJsonMap(
        'run_backtest',
        {
          'pair': _selectedPair,
          'startDate': _startDate!.toIso8601String(),
          'endDate': _endDate!.toIso8601String(),
          'timeframes': timeframePayload,
          'indicators': indicatorsPayload,
          'filters': filtersPayload,
          'exitRules': exitRulesPayload,
        },
      );
      if (body['error'] != null) {
        _setError(body['error'].toString());
        return;
      }
      final loads = body['loads'] as List<dynamic>? ?? [];

      _logs = [];
      var totalRows = 0;
      for (final item in loads) {
        if (item is Map && item['rows'] is num) {
          totalRows += (item['rows'] as num).toInt();
        }
      }
      final perf = body['performanceReport'];
      var signalCount = 0;
      if (perf is Map && perf['signalCount'] is num) {
        signalCount = (perf['signalCount'] as num).toInt();
      }
      _lastSignalCount = signalCount;

      // Log tecnici da run_backtest (probe GCS, exists, missing month, righe TF, …).
      final serverLogs = body['logs'];
      if (serverLogs is List && (totalRows == 0 || signalCount == 0)) {
        _logs.add('--- Diagnostica server (run_backtest, max 80 righe) ---');
        var i = 0;
        for (final line in serverLogs) {
          if (i++ >= 80) break;
          _logs.add(line.toString());
        }
        _logs.add('');
      }

      if (perf is Map) {
        final lot = perf['minLotPerTrade'];
        final sigs = perf['signalCount'];
        final pips = perf['totalRealizedPips'];
        final eur = perf['totalRealizedPnlEuro'];
        final note = perf['pnlNote'];
        final spPips = perf['totalSpreadRoundTripPips'];
        final spEur = perf['totalSpreadPaidEuro'];
        final spNote = perf['spreadNote'];
        _logs.add('--- Report strategia (conto in EUR) ---');
        _logs.add(
          'Lotto minimo: $lot | Segnali: $sigs | Σ pips: $pips | Σ P&L: $eur EUR',
        );
        if (spPips != null || spEur != null) {
          _logs.add(
            'Σ spread RT (1m Bid+Ask): ${spPips ?? 0} pips · ${spEur ?? 0} EUR',
          );
        }
        if (spNote != null) {
          _logs.add(spNote.toString());
        }
        if (note != null) {
          _logs.add(note.toString());
        }
      }
      final timingRaw = body['timing'];
      if (timingRaw is Map) {
        final t = Map<String, dynamic>.from(
          timingRaw.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (t.isNotEmpty) {
          _logs.add('--- Tempi esecuzione (server, ms) ---');
          void line(String label, String key) {
            final v = t[key];
            if (v != null) {
              _logs.add('$label: $v ms');
            }
          }
          line('Caricamento Parquet (GCS)', 'parquetLoadMs');
          line('Riepilogo righe per slot', 'loadsSummaryMs');
          line('Snapshot indicatori + exit plan', 'indicatorSnapshotAndExitPlanMs');
          line('Allineamento TF + generazione segnali', 'alignAndGenerateSignalsMs');
          line('Frame 1m (carico o riuso)', 'oneMinuteFrameMs');
          line('Simulazione uscite 1m', 'simulate1mMs');
          line('Salvataggio test_signals (Firestore)', 'replaceTestSignalsMs');
          line('Totale wall-clock', 'totalWallMs');
        }
      }
      _setStatus(TestStatus.success);
      _errorMessage = '';
    } on FirebaseFunctionsException catch (e) {
      _setError(e.message ?? e.toString());
    } catch (e) {
      _setError(e.toString());
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      _backtestProgressTitle = null;
      _backtestProgressSubtitle = null;
      notifyListeners();
    }
  }

  void _setStatus(TestStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _status = TestStatus.error;
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
