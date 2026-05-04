import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/error_handler.dart';
import '../datasources/firebase/firebase_auth_datasource.dart';
import '../datasources/firebase/firebase_firestore_datasource.dart';
import '../models/user_model.dart';
import 'auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuthDataSource _authDataSource;
  final FirebaseFirestoreDataSource _firestoreDataSource;

  // Utente corrente cache
  UserModel? _currentUser;

  AuthRepositoryImpl({
    FirebaseAuthDataSource? authDataSource,
    FirebaseFirestoreDataSource? firestoreDataSource,
  }) : _authDataSource = authDataSource ?? FirebaseAuthDataSource(),
       _firestoreDataSource =
           firestoreDataSource ?? FirebaseFirestoreDataSource() {
    // Ascolta i cambiamenti di stato di autenticazione per aggiornare la cache
    _authDataSource.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser == null) {
        _currentUser = null;
      } else {
        // Recupera il documento Firestore per avere i dati completi
        final userDoc = await _firestoreDataSource.getUserDocument(
          firebaseUser.uid,
        );
        if (userDoc != null) {
          _currentUser = userDoc;
        } else {
          // Se il documento non esiste (caso limite), crea un utente base
          _currentUser = UserModel(
            uid: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            fullName: null,
            isActive: false,
          );
        }
      }
    });
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  Stream<UserModel?> get authStateChanges {
    return _authDataSource.authStateChanges.asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      final userDoc = await _firestoreDataSource.getUserDocument(
        firebaseUser.uid,
      );
      if (userDoc != null) return userDoc;
      return UserModel(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        fullName: null,
        isActive: false,
      );
    });
  }

  @override
  Future<UserModel?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final authUser = await _authDataSource.signInWithEmailAndPassword(
        email,
        password,
      );
      if (authUser == null) {
        throw Exception('Email o password non validi.');
      }

      final firestoreUser = await _firestoreDataSource.getUserDocument(
        authUser.uid,
      );
      if (firestoreUser == null) {
        // Caso limite: utente autenticato ma senza documento Firestore
        final newUser = UserModel(
          uid: authUser.uid,
          email: authUser.email ?? '',
          fullName: null,
          isActive: false,
        );
        await _firestoreDataSource.createUserDocument(newUser);
        throw Exception('Account in attesa di attivazione.');
      }

      if (!firestoreUser.isActive) {
        throw Exception('Account non attivo. Contatta l\'assistenza.');
      }

      _currentUser = firestoreUser;
      return firestoreUser;
    } on FirebaseAuthException catch (e) {
      throw Exception(ErrorHandler.getFirebaseAuthErrorMessage(e));
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<UserModel?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final authUser = await _authDataSource.registerWithEmailAndPassword(
        email,
        password,
      );
      if (authUser == null) return null;

      final userModel = UserModel(
        uid: authUser.uid,
        email: authUser.email ?? '',
        fullName: fullName,
        isActive: false,
      );
      await _firestoreDataSource.createUserDocument(userModel);
      _currentUser = userModel;
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw Exception(ErrorHandler.getFirebaseAuthErrorMessage(e));
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await _authDataSource.sendPasswordResetEmail(email);
  }

  @override
  Future<void> signOut() async {
    await _authDataSource.signOut();
    _currentUser = null;
  }

  @override
  Future<void> createUserDocument(UserModel user) async {
    await _firestoreDataSource.createUserDocument(user);
  }
}
