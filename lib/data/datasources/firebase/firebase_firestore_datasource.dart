import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:strikezone/core/config/firebase_clients.dart';
import '../../models/user_model.dart';

class FirebaseFirestoreDataSource {
  late final FirebaseFirestore _firestore;

  FirebaseFirestoreDataSource() {
    _firestore = FirebaseClients.firestore();
  }

  Future<void> createUserDocument(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).set(user.toFirestore());
  }

  Future<UserModel?> getUserDocument(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc.data()!, uid);
    }
    return null;
  }

  Future<void> updateUserField(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update(data);
  }

  Stream<UserModel?> streamUserDocument(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromFirestore(doc.data()!, uid);
      }
      return null;
    });
  }
}
