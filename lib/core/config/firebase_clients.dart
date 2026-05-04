import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_runtime_config.dart';

class FirebaseClients {
  FirebaseClients._();

  static FirebaseFirestore firestore() {
    return FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: FirebaseRuntimeConfig.firestoreDatabaseId,
    );
  }
}
