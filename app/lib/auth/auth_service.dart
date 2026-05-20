import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _db;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Returns the signed-in user, or null if the user cancelled the Google sheet.
  /// Throws on Firebase errors so the UI can surface them.
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      await _ensureUserProfile(user);
    }
    return user;
  }

  Future<User?> signInAnonymously({required String displayName}) async {
    final result = await _auth.signInAnonymously();
    final user = result.user;
    if (user != null) {
      final trimmedName = displayName.trim();
      if (trimmedName.isNotEmpty) {
        await user.updateDisplayName(trimmedName);
        await user.reload();
      }
      await _ensureUserProfile(_auth.currentUser ?? user);
    }
    return _auth.currentUser ?? user;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Creates `users/{uid}` on first sign-in. Idempotent — merges if doc exists.
  Future<void> _ensureUserProfile(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (snap.exists) return;
    await docRef.set({
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'onboardingComplete': false,
    });
  }
}
