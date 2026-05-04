import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:strikezone/core/config/firebase_clients.dart';

import '../../../core/trading/fx_pair_utils.dart';
import '../../../data/models/signal_model.dart';
import '../../../data/repositories/signal_repository.dart';
import '../../../data/repositories/signal_repository_impl.dart';
import '../report_screen/report_view_model.dart';

bool _historyEpicSelectionCoversAll(Set<String> selected) {
  if (selected.length < kReportFilterEpics.length) return false;
  return kReportFilterEpics.every((e) => selected.contains(e.toUpperCase()));
}

enum HistoryFilterType { all, real, test }

class HistoryViewModel extends ChangeNotifier {
  late final FirebaseFirestore _firestore;
  final SignalRepository _signalRepository;
  String? _userId;
  List<SignalModel> _signals = [];
  bool _isLoading = true;
  String? _error;

  HistoryFilterType _typeFilter = HistoryFilterType.real;
  DateTime? _startDate;
  DateTime? _endDate;

  /// Sottoinsieme di [kReportFilterEpics]; tutte selezionate = nessun filtro (default come report).
  Set<String> _selectedEpics = Set<String>.from(kReportFilterEpics);

  StreamSubscription<QuerySnapshot>? _realSubscription;
  StreamSubscription<QuerySnapshot>? _testSubscription;

  HistoryViewModel({SignalRepository? signalRepository})
      : _signalRepository = signalRepository ?? SignalRepositoryImpl() {
    _firestore = FirebaseClients.firestore();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    if (_userId != null) {
      _listenToSignals();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _userId = user?.uid;
      if (_userId != null) {
        _listenToSignals();
      } else {
        _clearSubscriptions();
        _signals = [];
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  List<SignalModel> get signals => _signals;
  bool get isLoading => _isLoading;
  String? get error => _error;
  HistoryFilterType get typeFilter => _typeFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  Set<String> get selectedEpics => Set.unmodifiable(_selectedEpics);

  void setTypeFilter(HistoryFilterType filter) {
    _typeFilter = filter;
    _refreshSignals();
  }

  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    _refreshSignals();
  }

  void clearPairFilter() {
    _selectedEpics = Set<String>.from(kReportFilterEpics);
    _refreshSignals();
  }

  /// Non consente zero coppie: ritorna [kPairFilterAtLeastOneMessage] se l’utente deseleziona l’unica attiva.
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
    _refreshSignals();
    return null;
  }

  void _listenToSignals() {
    _clearSubscriptions();
    _isLoading = true;
    notifyListeners();

    _realSubscription = _firestore
        .collection('signals')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .listen(
          (_) {
            _updateSignals();
          },
          onError: (err) {
            _error = err.toString();
            _isLoading = false;
            notifyListeners();
          },
        );

    _testSubscription = _firestore
        .collection('test_signals')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .listen(
          (_) {
            _updateSignals();
          },
          onError: (err) {
            _error = err.toString();
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  Future<void> _updateSignals() async {
    try {
      List<SignalModel> allSignals = [];
      if (_typeFilter == HistoryFilterType.real ||
          _typeFilter == HistoryFilterType.all) {
        final realSnapshot = await _firestore
            .collection('signals')
            .where('userId', isEqualTo: _userId)
            .get();
        allSignals.addAll(
          realSnapshot.docs.map((doc) => SignalModel.fromFirestore(doc)),
        );
      }
      if (_typeFilter == HistoryFilterType.test ||
          _typeFilter == HistoryFilterType.all) {
        final testSnapshot = await _firestore
            .collection('test_signals')
            .where('userId', isEqualTo: _userId)
            .get();
        allSignals.addAll(
          testSnapshot.docs.map((doc) => SignalModel.fromFirestore(doc)),
        );
      }

      if (!_historyEpicSelectionCoversAll(_selectedEpics)) {
        allSignals = allSignals
            .where(
              (s) => _selectedEpics.contains(normalizedPairEpic(s.pair)),
            )
            .toList();
      }

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

      allSignals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _signals = allSignals;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void _refreshSignals() {
    if (_userId != null) {
      _updateSignals();
    }
  }

  /// Aggiorna campi utente su Firestore per un segnale dalla collezione `signals`.
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
      return 'Modifica disponibile solo per segnali reali.';
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

  void _clearSubscriptions() {
    _realSubscription?.cancel();
    _testSubscription?.cancel();
  }

  @override
  void dispose() {
    _clearSubscriptions();
    super.dispose();
  }
}
