import 'membership.dart';

abstract interface class MembershipRepository {
  Future<Membership?> current(String userId);
  Future<void> request(String parishId);
  Future<void> leave();
}
