import 'dart:convert';
import 'package:uuid/uuid.dart';

class DeviceProfile {
  final String id;
  final String displayName;
  final String avatarId;
  final String? customAvatarPath;
  final String platform;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOnboardingComplete;

  DeviceProfile({
    String? id,
    required this.displayName,
    this.avatarId = 'laptop',
    this.customAvatarPath,
    this.platform = 'unknown',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isOnboardingComplete = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isCustomAvatar => avatarId == 'custom' && customAvatarPath != null;

  DeviceProfile copyWith({
    String? displayName,
    String? avatarId,
    String? customAvatarPath,
    bool clearCustomAvatar = false,
    String? platform,
    DateTime? updatedAt,
    bool? isOnboardingComplete,
  }) {
    return DeviceProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      avatarId: avatarId ?? this.avatarId,
      customAvatarPath: clearCustomAvatar
          ? null
          : (customAvatarPath ?? this.customAvatarPath),
      platform: platform ?? this.platform,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isOnboardingComplete:
          isOnboardingComplete ?? this.isOnboardingComplete,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'avatarId': avatarId,
      'customAvatarPath': customAvatarPath,
      'platform': platform,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isOnboardingComplete': isOnboardingComplete,
    };
  }

  factory DeviceProfile.fromMap(Map<String, dynamic> map) {
    return DeviceProfile(
      id: map['id'] as String? ?? const Uuid().v4(),
      displayName: map['displayName'] as String? ?? 'My Device',
      avatarId: map['avatarId'] as String? ?? 'laptop',
      customAvatarPath: map['customAvatarPath'] as String?,
      platform: map['platform'] as String? ?? 'unknown',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      isOnboardingComplete: map['isOnboardingComplete'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DeviceProfile.fromJson(String source) =>
      DeviceProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'DeviceProfile(id: $id, displayName: $displayName, avatarId: $avatarId, isOnboardingComplete: $isOnboardingComplete)';
  }
}
