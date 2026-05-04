import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:strikezone/core/config/firebase_clients.dart';
import 'package:strikezone/core/firebase/cloud_functions_bridge.dart';
import '../models/signal_model.dart';
import 'signal_repository.dart';

class SignalRepositoryImpl implements SignalRepository {
  final FirebaseFirestore _firestore;

  SignalRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseClients.firestore();

  @override
  Stream<List<SignalModel>> watchUserSignals(String userId) {
    return _firestore
        .collection('signals')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SignalModel.fromFirestore(doc))
              .toList(),
        );
  }

  @override
  Future<void> markSignalAsProcessed(String signalId) async {
    await _firestore.collection('signals').doc(signalId).update({
      'isProcessed': true,
    });
  }

  @override
  Future<String> saveLiveSignal(Map<String, dynamic> signalPayload) async {
    final data = await CloudFunctionsBridge.callJsonMap(
      'save_live_signal',
      signalPayload,
      timeout: const Duration(seconds: 90),
    );
    final id = data['id'];
    if (data['ok'] == true && id is String && id.isNotEmpty) {
      return id;
    }
    throw StateError('save_live_signal: risposta non valida');
  }

  @override
  Future<void> updateLiveSignalUserFields({
    required String ownerUserId,
    required String signalId,
    required double entryPrice,
    required double stopLoss,
    required bool executionConfirmed,
    required bool clearExit,
    double? exitPrice,
    DateTime? exitTime,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != ownerUserId) {
      throw StateError('Non autenticato o utente non autorizzato.');
    }

    final ref = _firestore.collection('signals').doc(signalId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('Segnale non trovato.');
    }
    final data = snap.data();
    if (data == null || data['userId'] != ownerUserId) {
      throw StateError('Operazione non consentita su questo segnale.');
    }

    final update = <String, dynamic>{
      'entryPrice': entryPrice,
      'stopLoss': stopLoss,
      'executionConfirmed': executionConfirmed,
      'execution_confirmed': executionConfirmed,
    };

    if (clearExit) {
      update['exitPrice'] = FieldValue.delete();
      update['exitTime'] = FieldValue.delete();
      update['exit_price'] = FieldValue.delete();
      update['exit_time'] = FieldValue.delete();
      update['realizedPips'] = FieldValue.delete();
      update['realized_pips'] = FieldValue.delete();
    } else if (exitPrice != null) {
      final t = exitTime ?? DateTime.now();
      final ts = Timestamp.fromDate(t);
      update['exitPrice'] = exitPrice;
      update['exitTime'] = ts;
      update['exit_price'] = exitPrice;
      update['exit_time'] = ts;
    }

    await ref.update(update);
  }
}
