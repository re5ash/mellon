import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/notifications/application/notification_providers.dart';
import '../backend/backend_provider.dart';

class AccountAccess {
  const AccountAccess({
    this.restrictedGuest = false,
    this.superAdmin = false,
    this.canManageRoles = false,
    this.reviewStatus,
  });
  final bool restrictedGuest, superAdmin, canManageRoles;
  final String? reviewStatus;
  bool get awaitingReview => reviewStatus == 'pending';
  bool get reviewed => reviewStatus == 'verified';
  factory AccountAccess.fromJson(Map<String, dynamic> value) => AccountAccess(
    reviewStatus: value['review_status'] as String?,
    restrictedGuest: value['restricted_guest'] == true,
    superAdmin: value['super_admin'] == true,
    canManageRoles: value['can_manage_roles'] == true,
  );
}

final accountAccessRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final signal = ValueNotifier<int>(0);
  ref.onDispose(signal.dispose);
  return signal;
});

// Retain the last confirmed access while polling; a slow refresh must never
// temporarily turn a restricted guest back into an ordinary participant.
final accountAccessProvider = StreamProvider<AccountAccess>((ref) {
  final user = ref.watch(authUserProvider.select((v) => v.asData?.value?.id));
  if (user == null) return Stream.value(const AccountAccess());
  final client = ref.watch(backendProvider);
  final output = StreamController<AccountAccess>();
  bool disposed = false, busy = false, received = false, queued = false;
  Future<void> refresh() async {
    if (disposed) return;
    if (busy) {
      queued = true;
      return;
    }
    busy = true;
    try {
      final value = AccountAccess.fromJson(
        await client
            .rpc<Map<String, dynamic>>('my_account_access')
            .timeout(const Duration(seconds: 15)),
      );
      if (!disposed) {
        received = true;
        output.add(value);
      }
    } on Object catch (e, stack) {
      if (!disposed && !received) output.addError(e, stack);
    } finally {
      busy = false;
      if (queued && !disposed) {
        queued = false;
        unawaited(refresh());
      }
    }
  }

  ref.listen(
    notificationsProvider.select(
      (v) => v.asData?.value.map((n) => n.id).join(','),
    ),
    (previous, next) {
      if (next != null && next != previous) unawaited(refresh());
    },
  );
  final signal = ref.watch(accountAccessRefreshProvider);
  void requested() => unawaited(refresh());
  signal.addListener(requested);
  ref.onDispose(() => signal.removeListener(requested));
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => unawaited(refresh()),
  );
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    unawaited(output.close());
  });
  unawaited(refresh());
  return output.stream;
}, retry: (_, error) => null);
