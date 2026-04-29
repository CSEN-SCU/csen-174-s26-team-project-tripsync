class UserPreferences {
  final String userId;
  final Set<String> interests;

  const UserPreferences({
    required this.userId,
    required this.interests,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'interests': interests.toList(),
      };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      userId: json['userId'] as String,
      interests: (json['interests'] as List).cast<String>().toSet(),
    );
  }
}
