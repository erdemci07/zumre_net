import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user?.uid;

      if (uid == null) {
        await _auth.signOut();
        throw FirebaseAuthException(code: 'invalid-credential');
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));

      if (!userDoc.exists) {
        await _auth.signOut();
        throw FirebaseAuthException(code: 'invalid-credential');
      }

      notifyListeners();
    } catch (_) {
      await _auth.signOut();
      throw FirebaseAuthException(code: 'invalid-credential');
    }
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
        await _auth.signOut();
        return null;
      }

      return doc.data();
    } catch (_) {
      await _auth.signOut();
      return null;
    }
  }
}