class ClubRegistration {
  const ClubRegistration({
    required this.givenName,
    required this.familyName,
    required this.birthDate,
    required this.email,
    required this.password,
    required this.youthId,
    required this.receiptKey,
  });
  final String givenName, familyName, email, password, receiptKey;
  final String? youthId;
  final DateTime birthDate;

  Map<String, dynamic> get metadata => {
    'club_registration': {
      if (youthId != null) 'youth_id': youthId,
      if (youthId != null) 'receipt_key': receiptKey,
      'given_name': givenName.trim(),
      'family_name': familyName.trim(),
      'birth_date':
          '${birthDate.year.toString().padLeft(4, '0')}-'
          '${birthDate.month.toString().padLeft(2, '0')}-'
          '${birthDate.day.toString().padLeft(2, '0')}',
    },
  };
}

abstract interface class ClubRegistrationRepository {
  /// True means that email confirmation is required before joining the club.
  Future<bool> register(ClubRegistration registration);
}

class ClubChoice {
  const ClubChoice({
    required this.id,
    required this.name,
    required this.parishName,
  });
  final String id, name, parishName;
  String get label => '$name · $parishName';
}
