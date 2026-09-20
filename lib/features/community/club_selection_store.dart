import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/theme_controller.dart';

abstract interface class ClubSelectionStore {
  Future<String?> load(String actor);
  Future<void> save(String actor, String club);
}

class PreferencesClubSelectionStore implements ClubSelectionStore {
  const PreferencesClubSelectionStore(this.preferences);
  final SharedPreferencesAsync preferences;
  @override
  Future<String?> load(String actor) =>
      preferences.getString('selected-club:$actor');
  @override
  Future<void> save(String actor, String club) =>
      preferences.setString('selected-club:$actor', club);
}

final clubSelectionStoreProvider = Provider<ClubSelectionStore>(
  (ref) => PreferencesClubSelectionStore(ref.watch(preferencesProvider)),
);
final savedClubSelectionProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, actor) async {
      try {
        return await ref
            .watch(clubSelectionStoreProvider)
            .load(actor)
            .timeout(const Duration(seconds: 2));
      } on Object {
        // Storage disabled/private browsing: the club can still be selected normally.
        return null;
      }
    }, retry: (_, error) => null);
