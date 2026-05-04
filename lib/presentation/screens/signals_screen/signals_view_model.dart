// lib/presentation/screens/signals_screen/signals_view_model.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/config/firebase_clients.dart';
import '../../../core/firebase/cloud_functions_bridge.dart';
import '../../../data/models/signal_model.dart';
import '../../../data/repositories/signal_repository.dart';

class SignalsViewModel extends ChangeNotifier {
  /// Coppie interrogate da Capital per la valutazione live (manuale e timer quando `pairs` è omesso).
  static const List<String> defaultLiveEvaluationPairs = [
    'EURUSD',
    'GBPUSD',
    'GBPJPY',
  ];

  final SignalRepository _signalRepository;
  List<SignalModel> _allSignals = [];
  bool _isLoading = true;
  StreamSubscription<List<SignalModel>>? _signalsSubscription;

  bool _capitalEvalLoading = false;
  String? _capitalEvalError;
  String? _lastCapitalEvalSummary;

  int _liveEvalIntervalMinutes = 5;
  bool _liveEvalEnabled = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _strategyConfigSubscription;
  Timer? _liveEvalTimer;
  bool _liveEvalInFlight = false;

  SignalsViewModel(this._signalRepository) {
    _listenToSignals();
    _listenLiveSignalEvaluation();
  }

  /// Intervallo (minuti) letto da `strategy_configs.liveSignalEvaluation` (default 5).
  int get liveEvalIntervalMinutes => _liveEvalIntervalMinutes;

  /// Se false, nessun timer periodico verso `run_live_signals_from_capital`.
  bool get liveEvalEnabled => _liveEvalEnabled;

  /// Segnali live ancora aperti (nessuna uscita registrata).
  List<SignalModel> get activeSignals =>
      _allSignals.where((s) => !s.isClosed).toList();

  int get activeSignalCount => activeSignals.length;

  bool get isLoading => _isLoading;

  bool get isCapitalEvalLoading => _capitalEvalLoading;

  String? get capitalEvalError => _capitalEvalError;

  /// Breve riepilogo ultima chiamata a [runLiveStrategyFromCapital].
  String? get lastCapitalEvalSummary => _lastCapitalEvalSummary;

  void _listenToSignals() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    _signalsSubscription = _signalRepository
        .watchUserSignals(user.uid)
        .listen(
          (signals) {
            _allSignals = signals;
            _isLoading = false;
            notifyListeners();
          },
          onError: (error) {
            debugPrint('Errore nel caricamento segnali: $error');
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  void _listenLiveSignalEvaluation() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _strategyConfigSubscription?.cancel();
    _strategyConfigSubscription = FirebaseClients.firestore()
        .collection('strategy_configs')
        .doc(user.uid)
        .snapshots()
        .listen(
      (snap) {
        final d = snap.data();
        final live = d?['liveSignalEvaluation'];
        int mins = 5;
        var enabled = true;
        if (live is Map) {
          enabled = live['enabled'] != false;
          final m = live['intervalMinutes'];
          if (m is num) mins = m.toInt().clamp(2, 120);
        }
        final changed =
            mins != _liveEvalIntervalMinutes || enabled != _liveEvalEnabled;
        _liveEvalIntervalMinutes = mins;
        _liveEvalEnabled = enabled;
        if (changed) notifyListeners();
        _rescheduleLiveEvalTimer();
      },
      onError: (Object e) => debugPrint('strategy_configs stream: $e'),
    );
  }

  void _rescheduleLiveEvalTimer() {
    _liveEvalTimer?.cancel();
    _liveEvalTimer = null;
    if (!_liveEvalEnabled) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    _liveEvalTimer = Timer.periodic(
      Duration(minutes: _liveEvalIntervalMinutes),
      (_) {
        unawaited(_onLiveEvalTick());
      },
    );
  }

  Future<void> _onLiveEvalTick() async {
    if (_liveEvalInFlight) return;
    _liveEvalInFlight = true;
    try {
      await runLiveStrategyFromCapital(silent: true);
    } finally {
      _liveEvalInFlight = false;
    }
  }

  Future<void> refreshSignals() async {
    _signalsSubscription?.cancel();
    _listenToSignals();
  }

  /// Aggiorna prezzo ingresso, SL, chiusura e conferma esecuzione su `signals/{id}`.
  Future<String?> submitLiveSignalEdits(
    SignalModel signal, {
    required double entryPrice,
    required double stopLoss,
    required bool executionConfirmed,
    required bool clearExit,
    double? exitPrice,
    DateTime? exitTime,
  }) async {
    if (signal.documentSource != SignalFirestoreCollection.live) {
      return 'Segnale non modificabile.';
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != signal.userId) {
      return 'Utente non autorizzato.';
    }
    try {
      await _signalRepository.updateLiveSignalUserFields(
        ownerUserId: signal.userId,
        signalId: signal.id,
        entryPrice: entryPrice,
        stopLoss: stopLoss,
        executionConfirmed: executionConfirmed,
        clearExit: clearExit,
        exitPrice: exitPrice,
        exitTime: exitTime,
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Chiama la Cloud Function `run_live_signals_from_capital` (OHLC Capital + stessa logica backtest).
  ///
  /// [pairs] se null usa le tre coppie principali come sul feed quotazioni.
  Future<void> runLiveStrategyFromCapital({
    List<String>? pairs,
    bool silent = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!silent) {
        _capitalEvalError = 'Accedi per valutare la strategia.';
        notifyListeners();
      }
      return;
    }

    if (!silent) {
      _capitalEvalLoading = true;
      _capitalEvalError = null;
      _lastCapitalEvalSummary = null;
      notifyListeners();
    }

    try {
      final data = await CloudFunctionsBridge.callJsonMap(
        'run_live_signals_from_capital',
        {
          'pairs': pairs ?? defaultLiveEvaluationPairs,
          'maxBars': 400,
        },
        timeout: const Duration(seconds: 120),
      );
      final saved = data['saved'];
      final errs = data['errors'];
      final ok = data['ok'] == true;

      final nSaved =
          saved is List ? saved.length : 0;
      final errList = errs is List ? errs.map((e) => e.toString()).join('; ') : '';

      if (!silent) {
        if (!ok && nSaved == 0) {
          _capitalEvalError = errList.isNotEmpty
              ? errList
              : 'Nessun segnale salvato (verifica credenziali Capital e timeframe).';
        } else {
          _lastCapitalEvalSummary = nSaved > 0
              ? 'Salvati $nSaved segnali live.'
              : 'Valutazione completata: nessun nuovo segnale sull’ultima barra.';
          if (errList.isNotEmpty) {
            _lastCapitalEvalSummary =
                '${_lastCapitalEvalSummary!} Avvisi: $errList';
          }
        }
      } else if (!ok && nSaved == 0 && errList.isNotEmpty) {
        debugPrint('runLiveStrategyFromCapital (silent): $errList');
      }

      await refreshSignals();
    } on FirebaseFunctionsException catch (e) {
      if (!silent) {
        _capitalEvalError = e.message ?? e.code;
      } else {
        debugPrint('runLiveStrategyFromCapital (silent): ${e.message}');
      }
    } catch (e) {
      if (!silent) {
        _capitalEvalError = e.toString();
      } else {
        debugPrint('runLiveStrategyFromCapital (silent): $e');
      }
    } finally {
      if (!silent) {
        _capitalEvalLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _signalsSubscription?.cancel();
    _strategyConfigSubscription?.cancel();
    _liveEvalTimer?.cancel();
    super.dispose();
  }
}
