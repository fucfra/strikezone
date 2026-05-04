import '../models/signal_model.dart';

abstract class SignalRepository {
  Stream<List<SignalModel>> watchUserSignals(String userId);
  Future<void> markSignalAsProcessed(String signalId);

  /// Salva un segnale live via Cloud Function `save_live_signal` (rispetta maxSimultaneousTrades).
  /// Restituisce l'id documento Firestore.
  Future<String> saveLiveSignal(Map<String, dynamic> signalPayload);

  /// Aggiorna su `signals/{signalId}` prezzo ingresso, SL, uscita e flag esecuzione (solo proprietario).
  ///
  /// Se [clearExit] è true rimuove chiusura e pips realizzati salvati. Altrimenti, se [exitPrice]
  /// non è null, imposta chiusura con [exitTime] (tipicamente `DateTime.now()` se il prezzo di
  /// chiusura è stato modificato).
  Future<void> updateLiveSignalUserFields({
    required String ownerUserId,
    required String signalId,
    required double entryPrice,
    required double stopLoss,
    required bool executionConfirmed,
    required bool clearExit,
    double? exitPrice,
    DateTime? exitTime,
  });
}
