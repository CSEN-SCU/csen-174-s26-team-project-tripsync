import 'package:cloud_firestore/cloud_firestore.dart';

import 'preferences_service.dart';
import 'user_preferences.dart';

class FirestorePreferencesService implements PreferencesService {
  FirestorePreferencesService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _db.collection('users').doc(userId);

  @override
  Future<UserPreferences?> load(String userId) async {
    final snap = await _userDoc(userId).get();
    final data = snap.data();
    if (data == null) return null;
    final prefs = data['preferences'] as Map<String, dynamic>?;
    if (prefs == null) return null;
    final rawInterests = (prefs['interests'] as List?)?.cast<String>() ?? const [];
    return UserPreferences(userId: userId, interests: rawInterests.toSet());
  }

  @override
  Future<void> save(String userId, Set<String> interests) async {
    await _userDoc(userId).set({
      'preferences': {
        'interests': interests.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'onboardingComplete': true,
    }, SetOptions(merge: true));
  }
}
