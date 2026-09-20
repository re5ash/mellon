class AppUser {
  const AppUser(this.id);
  final String id;

  // Session refreshes describe the same account. Consumers should reload only
  // when the account identity changes, not on every refreshed access token.
  @override
  bool operator ==(Object other) => other is AppUser && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
