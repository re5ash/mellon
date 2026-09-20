enum ProfileVisibility {
  private,
  parish;

  static ProfileVisibility fromJson(String value) =>
      ProfileVisibility.values.byName(value);
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.visibility,
    required this.givenName,
    required this.familyName,
    required this.birthDate,
    required this.profileRevision,
    required this.privateRevision,
    this.phone = '',
    this.email = '',
    this.avatarPath,
    this.parishName,
    this.youthName,
  });

  final String userId, displayName, givenName, familyName;
  final String phone, email;
  final String? avatarPath, parishName, youthName;
  final ProfileVisibility visibility;
  // A calendar date, not an instant. Never convert it between time zones.
  final DateTime? birthDate;
  final int profileRevision, privateRevision;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String,
    visibility: ProfileVisibility.fromJson(
      json['directory_visibility'] as String,
    ),
    givenName: json['given_name'] as String,
    familyName: json['family_name'] as String,
    birthDate: json['birth_date'] == null
        ? null
        : DateTime.parse(json['birth_date'] as String),
    profileRevision: (json['profile_revision'] as num).toInt(),
    privateRevision: (json['private_revision'] as num).toInt(),
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    avatarPath: json['avatar_path'] as String?,
    parishName: json['parish_name'] as String?,
    youthName: json['youth_name'] as String?,
  );
}

class ProfileInput {
  const ProfileInput({
    required this.expectedUserId,
    required this.displayName,
    required this.visibility,
    required this.givenName,
    required this.familyName,
    required this.birthDate,
    required this.profileRevision,
    required this.privateRevision,
    this.phone = '',
  });

  final String expectedUserId, displayName, givenName, familyName, phone;
  final ProfileVisibility visibility;
  final DateTime? birthDate;
  final int profileRevision, privateRevision;

  Map<String, Object?> toRpc() => {
    'p_expected_user_id': expectedUserId,
    'p_display_name': displayName.trim(),
    'p_directory_visibility': visibility.name,
    'p_given_name': givenName.trim(),
    'p_family_name': familyName.trim(),
    'p_birth_date': birthDate == null ? null : calendarDate(birthDate!),
    'p_profile_revision': profileRevision,
    'p_private_revision': privateRevision,
    'p_phone': phone.trim(),
  };
}

String calendarDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
