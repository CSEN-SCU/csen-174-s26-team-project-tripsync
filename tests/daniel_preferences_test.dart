import 'package:test/test.dart';
import '../userOnboarding/user_preferences.dart';
import '../userOnboarding/preferences_service.dart';

void main() {
  group('UserPreferences', () {
    // As a user, my chosen interests survive being saved and loaded back.
    test('round-trips through JSON without losing data', () {
      // Arrange
      final prefs = UserPreferences(
        userId: 'u123',
        interests: {'climbing', 'food', 'history'},
      );

      // Action
      final restored = UserPreferences.fromJson(prefs.toJson());

      // Assert
      expect(restored.userId, equals('u123'));
      expect(restored.interests, equals({'climbing', 'food', 'history'}));
    });
  });

  group('FakePreferencesService', () {
    // As a returning user, I see the same interests I picked during onboarding.
    test('save then load returns the same interests', () async {
      // Arrange
      final service = FakePreferencesService();

      // Action
      await service.save('u123', {'climbing', 'food'});
      final loaded = await service.load('u123');

      // Assert
      expect(loaded, isNotNull);
      expect(loaded!.userId, equals('u123'));
      expect(loaded.interests, equals({'climbing', 'food'}));
    });

    // As a brand-new user with nothing saved yet, loading returns nothing instead of crashing.
    test('load returns null for an unknown user', () async {
      // Arrange
      final service = FakePreferencesService();

      // Action
      final loaded = await service.load('never-saved');

      // Assert
      expect(loaded, isNull);
    });
  });
}
