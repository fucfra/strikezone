import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/firebase_runtime_config.dart';
import '../../data/models/quote_model.dart';
import '../../firebase_options.dart';

enum MarketDataStatus { connecting, connected, error, disconnected }

class MarketDataProvider extends ChangeNotifier {
  MarketDataStatus _status = MarketDataStatus.disconnected;
  String? _errorMessage;
  final List<QuoteModel> _liveQuotes = [];
  final Map<String, QuoteModel> _quotesMap = {};
  Timer? _pollingTimer;
  bool _fetchQuotesInFlight = false;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Coppie aggiornate automaticamente (GET `/api/v1/markets/{epic}` via proxy).
  static const List<String> _epics = ['EURUSD', 'GBPUSD', 'GBPJPY'];

  /// Capital.com: non più di **10 richieste HTTP al secondo** per utente/chiave API
  /// (limite principale documentato; altri dettagli sul sito “API limitations”).
  /// Fonte: https://help.capital.com/hc/en-us/articles/6630830103058-Do-you-have-any-limitations-on-your-API
  ///
  /// Non risulta un tetto orario pubblico generico per i GET mercato; il polling resta
  /// sotto il limite per-secondo usando una frazione del budget e un minimo di secondi tra cicli.
  static const int _capitalDocumentedMaxRequestsPerSecond = 10;

  /// Usiamo al massimo questa frazione del budget 10 req/s **solo** per il polling quotazioni
  /// (restano margine sessioni Capital su Cloud Functions, altre schermate, ecc.).
  static const double _quotePollBudgetFraction = 0.22;

  /// Pausa tra un GET mercato e il successivo (stesso ciclo) per evitare picchi ravvicinati.
  static const Duration _delayBetweenEpicRequests = Duration(milliseconds: 150);

  static Duration get _quotePollInterval {
    final n = _epics.length;
    final budgetPerSec = _capitalDocumentedMaxRequestsPerSecond * _quotePollBudgetFraction;
    final theoreticalMinSec = (n / budgetPerSec).ceil();
    const practicalMinSec = 12;
    const practicalMaxSec = 90;
    final sec = math.min(
      practicalMaxSec,
      math.max(practicalMinSec, theoreticalMinSec),
    );
    return Duration(seconds: sec);
  }

  /// Intervallo tra un ciclo completo di refresh e il successivo (documentato in UI / test).
  static Duration get quoteAutoRefreshInterval => _quotePollInterval;

  MarketDataProvider() {
    init();
  }

  MarketDataStatus get status => _status;
  String? get errorMessage => _errorMessage;
  List<QuoteModel> get liveQuotes => List.unmodifiable(_liveQuotes);

  Future<void> init() async {
    if (_disposed) return;
    _status = MarketDataStatus.connecting;
    _safeNotify();

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      _quotePollInterval,
      (_) {
        if (!_disposed) _fetchQuotes();
      },
    );
    await _fetchQuotes();
  }

  Future<void> _fetchQuotes() async {
    if (_disposed) return;
    if (_fetchQuotesInFlight) {
      return;
    }
    _fetchQuotesInFlight = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (_disposed) return;
        _status = MarketDataStatus.disconnected;
        _safeNotify();
        return;
      }

      final idToken = await user.getIdToken();
      if (_disposed) return;
      final useHttpProxy = FirebaseRuntimeConfig.useEmulator;
      final uri = useHttpProxy
          ? Uri.parse(
              FirebaseRuntimeConfig.onRequestFunctionUrl(
                projectId: DefaultFirebaseOptions.currentPlatform.projectId,
                functionName: 'capital_com_proxy',
              ),
            )
          : null;
      final callable = useHttpProxy
          ? null
          : FirebaseFunctions.instance.httpsCallable(
              'capital_com_proxy_call',
            );

      for (var i = 0; i < _epics.length; i++) {
        final epic = _epics[i];
        if (_disposed) return;
        late final Map<String, dynamic> data;
        try {
          if (useHttpProxy) {
            final response = await http
                .post(
                  uri!,
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $idToken',
                  },
                  body: jsonEncode({
                    'endpoint': '/api/v1/markets/$epic',
                    'method': 'GET',
                  }),
                )
                .timeout(const Duration(seconds: 90));
            if (response.statusCode != 200) {
              _setError(
                'Errore quote $epic: HTTP ${response.statusCode} ${response.body}',
              );
              return;
            }
            data = jsonDecode(response.body) as Map<String, dynamic>;
          } else {
            final result = await callable!
                .call<Map<String, dynamic>>({
                  'endpoint': '/api/v1/markets/$epic',
                  'method': 'GET',
                })
                .timeout(const Duration(seconds: 90));
            data = Map<String, dynamic>.from(result.data);
          }
        } on FirebaseFunctionsException catch (e) {
          _setError(
            'Errore quote $epic: ${e.message ?? e.code}',
          );
          return;
        } catch (e) {
          _setError('Errore rete quote $epic: $e');
          return;
        }

        final innerStatus = data['status'];
        if (innerStatus is num && innerStatus != 200) {
          _setError('Errore quote $epic: Capital API $innerStatus');
          return;
        }

        final Map<String, dynamic>? marketData =
            data['data'] is Map
                ? Map<String, dynamic>.from(data['data'] as Map)
                : null;
        if (marketData != null && marketData['snapshot'] != null) {
          final snapshot = marketData['snapshot'] as Map<String, dynamic>;
          final updateTimeStr = snapshot['updateTime'] as String;
          final updateTime = DateTime.parse(updateTimeStr);

          double? optNum(String key) {
            final v = snapshot[key];
            if (v == null) return null;
            if (v is num) return v.toDouble();
            return null;
          }

          final quote = QuoteModel(
            epic: epic,
            bid: (snapshot['bid'] as num).toDouble(),
            ofr: (snapshot['offer'] as num).toDouble(),
            price: ((snapshot['bid'] as num) + (snapshot['offer'] as num)) / 2,
            timestamp: updateTime.millisecondsSinceEpoch,
            marketStatus: snapshot['marketStatus'] as String,
            updateTime: updateTime,
            high: optNum('high'),
            low: optNum('low'),
            percentageChange: optNum('percentageChange'),
            netChange: optNum('netChange'),
            decimalPlacesFactor:
                (snapshot['decimalPlacesFactor'] as num?)?.toInt(),
          );
          _quotesMap[epic] = quote;
        }
        if (i < _epics.length - 1) {
          await Future<void>.delayed(_delayBetweenEpicRequests);
        }
      }
      if (_disposed) return;
      _updateQuotesList();

      if (_liveQuotes.isNotEmpty && _status == MarketDataStatus.connecting) {
        _status = MarketDataStatus.connected;
        _errorMessage = null;
      }
      _safeNotify();
    } finally {
      _fetchQuotesInFlight = false;
    }
  }

  void _updateQuotesList() {
    if (_disposed) return;
    _liveQuotes.clear();
    for (final epic in _epics) {
      if (_quotesMap.containsKey(epic)) {
        _liveQuotes.add(_quotesMap[epic]!);
      }
    }
    _safeNotify();
  }

  void _setError(String msg) {
    if (_disposed) return;
    _errorMessage = msg;
    _status = MarketDataStatus.error;
    _safeNotify();
  }

  void refreshConnection() {
    if (_disposed) return;
    _quotesMap.clear();
    _liveQuotes.clear();
    _fetchQuotes();
  }

  void reconnect() {
    refreshConnection();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    super.dispose();
  }
}
