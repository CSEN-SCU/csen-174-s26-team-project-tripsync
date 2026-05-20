import 'user_preferences.dart';

abstract class PreferencesService {
  Future<UserPreferences?> load(String userId);
  Future<void> save(String userId, Set<String> interests);
}

class FakePreferencesService implements PreferencesService {
  final Map<String, UserPreferences> _store = {};

  @override
  Future<UserPreferences?> load(String userId) async => _store[userId];

  @override
  Future<void> save(String userId, Set<String> interests) async {
    _store[userId] = UserPreferences(userId: userId, interests: interests);
  }
}
