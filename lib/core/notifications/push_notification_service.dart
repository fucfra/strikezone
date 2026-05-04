import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/firebase_clients.dart';

/// Registra FCM, salva i token su `users/{uid}.fcmTokens` (array) per le Cloud Functions.
///
/// Web: richiede VAPID e service worker configurati in Firebase Console / FlutterFire;
/// se il token non è disponibile, il salvataggio viene ignorato senza errori fatali.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<String>? _tokenRefreshSub;

  Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.setAutoInitEnabled(true);
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (kDebugMode) {
        debugPrint('FCM permission: ${settings.authorizationStatus}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM requestPermission: $e');
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final t = msg.notification?.title ?? 'Strikezone';
      final b = msg.notification?.body ?? '';
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('$t\n$b')),
      );
    });

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (t) => _saveTokenForCurrentUser(t),
    );

    await syncTokenForCurrentUser();
  }

  Future<void> syncTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveTokenForUser(user.uid, token);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM getToken: $e');
      }
    }
  }

  Future<void> _saveTokenForCurrentUser(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _saveTokenForUser(user.uid, token);
  }

  Future<void> _saveTokenForUser(String uid, String token) async {
    await FirebaseClients.firestore().collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }
}
