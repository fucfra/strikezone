import 'package:firebase_auth/firebase_auth.dart';

class ErrorHandler {
  static String getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Nessun utente trovato con questa email.';
      case 'wrong-password':
        return 'Password errata.';
      case 'email-already-in-use':
        return 'Questa email è già registrata.';
      case 'weak-password':
        return 'La password è troppo debole (minimo 6 caratteri).';
      case 'invalid-email':
        return 'Formato email non valido.';
      case 'too-many-requests':
        return 'Troppe richieste. Riprova più tardi.';
      case 'network-request-failed':
        return 'Errore di connessione. Controlla la tua rete.';
      default:
        return e.message ?? 'Errore di autenticazione sconosciuto.';
    }
  }

  static String getFirestoreErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permessi insufficienti per completare l\'operazione.';
      case 'not-found':
        return 'Documento non trovato.';
      case 'already-exists':
        return 'Il documento esiste già.';
      default:
        return e.message ?? 'Errore del database.';
    }
  }
}
