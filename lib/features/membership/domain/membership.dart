class Membership {
  const Membership({
    required this.id,
    required this.parishId,
    required this.status,
  });
  final String id;
  final String parishId;
  final String status;
  bool get isActive => status == 'active';
  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
    id: json['id'] as String,
    parishId: json['parish_id'] as String,
    status: json['status'] as String,
  );
}
