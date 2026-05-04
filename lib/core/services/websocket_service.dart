import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:http/http.dart' as http;

import '../../data/models/quote_model.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  static const String _baseUrl = 'https://demo-api-capital.backend-capital.com';
  static const String _wsUrl =
      'wss://demo-api-capital.backend-capital.com/connect';

  // Token di autenticazione
  String? _cst;
  String? _securityToken;

  IOWebSocketChannel? _channel;
  final StreamController<QuoteModel> _quoteController =
      StreamController.broadcast();
  final StreamController<String> _statusController =
      StreamController.broadcast();

  Timer? _pingTimer;
  int _correlationId = 0;

  Stream<QuoteModel> get quoteStream => _quoteController.stream;
  Stream<String> get statusStream => _statusController.stream;

  // 1) Autenticazione e recupero token
  Future<bool> authenticate(
    String apiKey,
    String login,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/session'),
        headers: {'Content-Type': 'application/json', 'X-CAP-API-KEY': apiKey},
        body: jsonEncode({'identifier': login, 'password': password}),
      );

      if (response.statusCode == 200) {
        _cst = response.headers['cst'];
        _securityToken = response.headers['x-security-token'];
        _statusController.add('Authenticated');
        return true;
      } else {
        _statusController.add('Auth failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _statusController.add('Auth error: $e');
      return false;
    }
  }

  // 2) Connessione WebSocket
  void connect() {
    if (_channel != null) return;

    _channel = IOWebSocketChannel.connect(Uri.parse(_wsUrl));
    _statusController.add('Connecting...');

    _channel!.stream.listen(
      (message) => _handleMessage(message),
      onError: (error) {
        _statusController.add('WebSocket error: $error');
        _reconnect();
      },
      onDone: () {
        _statusController.add('WebSocket disconnected');
        _reconnect();
      },
    );

    // Attiviamo il ping ogni 5 minuti (limite sessione è 10 minuti)
    _startPing();
  }

  // 3) Sottoscrizione a uno o più epic
  void subscribe(List<String> epics) {
    if (_channel == null) return;

    final request = {
      'destination': 'marketData.subscribe',
      'correlationId': '${++_correlationId}',
      'cst': _cst,
      'securityToken': _securityToken,
      'payload': {'epics': epics},
    };
    _channel!.sink.add(jsonEncode(request));
    _statusController.add('Subscribed to: ${epics.join(', ')}');
  }

  // 4) Disconnessione
  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _statusController.add('Disconnected');
  }

  // Gestione dei messaggi in arrivo
  void _handleMessage(String message) {
    final data = jsonDecode(message);
    final destination = data['destination'];

    if (destination == 'quote') {
      final quote = QuoteModel.fromJson(data['payload']);
      _quoteController.add(quote);
    } else if (destination == 'ping') {
      // risposta al ping, non facciamo nulla
    } else {
      // Altri messaggi di servizio
    }
  }

  // Invio periodico del ping per mantenere la connessione
  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_channel != null) {
        final ping = {
          'destination': 'ping',
          'correlationId': '${++_correlationId}',
          'cst': _cst,
          'securityToken': _securityToken,
        };
        _channel!.sink.add(jsonEncode(ping));
      }
    });
  }

  // Tentativo di riconnessione dopo 5 secondi
  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (_channel == null) {
        connect();
      }
    });
  }
}
