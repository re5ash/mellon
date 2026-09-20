import 'user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> read();
  Future<UserProfile> save(ProfileInput input);
}
