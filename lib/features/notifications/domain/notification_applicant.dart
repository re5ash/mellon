class NotificationApplicant {
  const NotificationApplicant({
    required this.notificationId,
    required this.userId,
    required this.displayName,
    required this.email,
    this.givenName = '',
    this.familyName = '',
    this.phone = '',
    this.birthDate,
    this.registeredAt,
    this.reviewStatus,
    this.clubId,
    this.clubName,
    this.requestId,
    this.requestStatus,
    this.canManageRoles = false,
  });
  factory NotificationApplicant.fromJson(Map<String, dynamic> json) =>
      NotificationApplicant(
        notificationId: json['notification_id'] as String,
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String,
        email: json['email'] as String? ?? '',
        givenName: json['given_name'] as String? ?? '',
        familyName: json['family_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        birthDate: DateTime.tryParse(json['birth_date'] as String? ?? ''),
        registeredAt: DateTime.tryParse(json['registered_at'] as String? ?? ''),
        reviewStatus: json['review_status'] as String?,
        clubId: json['youth_id'] as String?,
        clubName: json['youth_name'] as String?,
        requestId: json['request_id'] as String?,
        requestStatus: json['request_status'] as String?,
        canManageRoles: json['can_manage_roles'] == true,
      );
  final String notificationId, userId, displayName, email;
  final String givenName, familyName, phone;
  final DateTime? birthDate, registeredAt;
  final String? reviewStatus, clubId, clubName, requestId, requestStatus;
  final bool canManageRoles;
  String get name {
    final full = [
      givenName.trim(),
      familyName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? displayName : full;
  }

  String get status => switch (requestStatus) {
    'accepted' => 'Заявка принята',
    'rejected' => 'Проверен · доступ к клубу не открыт',
    _ => reviewStatus == 'verified' ? 'Проверен' : 'Ожидание проверки',
  };
}
