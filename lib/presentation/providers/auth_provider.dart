import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomAuthProvider extends ChangeNotifier {
  String? _userId;
  String? get userId => _userId;

  CustomAuthProvider() {
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      final newId = user?.uid;
      if (newId == _userId) {
        return;
      }
      _userId = newId;
      notifyListeners();
    });
  }
}
