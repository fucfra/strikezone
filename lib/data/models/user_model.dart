import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserModel {
  final String uid;
  final String email;
  final String? fullName;
  final String? avatar;
  final bool isActive;
  final DateTime? createdAt;

  UserModel({
    required this.uid,
    required this.email,
    this.fullName,
    this.avatar,
    this.isActive = true,
    this.createdAt,
  });

  factory UserModel.fromFirebase(User user) {
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      createdAt: user.metadata.creationTime,
    );
  }

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      fullName: data['fullName'],
      avatar: data['avatar'],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'fullName': fullName,
      'avatar': avatar,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
