import '../models/user_model.dart';

abstract class AuthRepository {
  UserModel? get currentUser;
  Stream<UserModel?> get authStateChanges;

  Future<UserModel?> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<UserModel?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
  });

  Future<void> sendPasswordResetEmail(String email);

  Future<void> signOut();

  Future<void> createUserDocument(UserModel user);
}
