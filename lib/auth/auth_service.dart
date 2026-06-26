import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

 Future<Map<String, dynamic>?> getUserRole(String uid) async {
  try {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 8));

    if (!doc.exists) {
      throw Exception('Kullanıcı Firestore kaydı bulunamadı.');
    }

    return doc.data();
  } catch (e) {
    print('GET USER ROLE HATASI: $e');
    rethrow;
  }
}
}