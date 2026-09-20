import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/backend_provider.dart';
import '../auth/application/auth_providers.dart';
import '../chats/application/chat_moderation.dart';
import '../chats/application/chat_providers.dart';
import '../map/application/map_providers.dart';
import 'club_applications_page.dart';
import 'club_dashboard_repository.dart';
import 'club_directory_repository.dart';
import 'club_photo_cache.dart';
import 'stories/story_repository.dart';

class ClubLiveUpdate {
  const ClubLiveUpdate({this.tables = const {}, this.reconnected = false});
  final Set<String> tables;
  final bool reconnected;
}

final clubLiveUpdatesProvider = StreamProvider.autoDispose<ClubLiveUpdate>((
  ref,
) {
  final actor = ref.watch(
    authUserProvider.select((value) => value.asData?.value?.id),
  );
  if (actor == null) return const Stream.empty();
  return ClubLiveUpdates(ref.watch(backendProvider)).watch(actor);
}, retry: (_, error) => null);

class ClubLiveUpdates {
  const ClubLiveUpdates(this.client);
  final SupabaseClient client;
  Stream<ClubLiveUpdate> watch(String actor) async* {
    final events = StreamController<ClubLiveUpdate>();
    Timer? debounce;
    final tables = <String>{};
    var reconnected = false;
    var disposed = false;
    void changed({String? table, bool connected = false}) {
      if (disposed) return;
      if (table != null) tables.add(table);
      reconnected = reconnected || connected;
      if (debounce?.isActive == true) return;
      debounce = Timer(const Duration(milliseconds: 250), () {
        if (!events.isClosed)
          events.add(
            ClubLiveUpdate(
              tables: Set<String>.unmodifiable(tables),
              reconnected: reconnected,
            ),
          );
        tables.clear();
        reconnected = false;
      });
    }

    final channel = client.channel('club-live:$actor');
    for (final table in [
      'chat_messages',
      'chat_rooms',
      'club_chat_reads',
      'youth_memberships',
      'youth_groups',
      'events',
      'feed_publication_changes',
      'help_requests',
      'club_stories',
      'notifications',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => changed(table: table),
      );
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed)
        changed(connected: true);
    });
    try {
      yield* events.stream;
    } finally {
      disposed = true;
      debounce?.cancel();
      await client.removeChannel(channel);
      await events.close();
    }
  }
}

/// One subscription for the club screen, not one for each row or message.
class ClubLiveScope extends ConsumerStatefulWidget {
  const ClubLiveScope({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<ClubLiveScope> createState() => _ClubLiveScopeState();
}

class _ClubLiveScopeState extends ConsumerState<ClubLiveScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refresh([
    ClubLiveUpdate update = const ClubLiveUpdate(reconnected: true),
  ]) {
    final membership =
        update.reconnected ||
        update.tables.any(
          {'youth_memberships', 'youth_groups', 'notifications'}.contains,
        );
    if (update.tables.contains('youth_memberships'))
      ref.invalidate(clubPhotoCacheProvider);
    if (update.reconnected || update.tables.contains('events') || membership) {
      ref.invalidate(mapEventsProvider);
    }
    if (membership || update.tables.contains('club_stories'))
      ref.invalidate(clubStoriesProvider);
    final rooms = membership || update.tables.contains('chat_rooms');
    // Messages/read receipts update the list without rebuilding the open chat.
    ref.invalidate(clubDashboardProvider);
    if (membership) {
      ref.invalidate(clubDirectoryProvider);
      ref.invalidate(clubEntryProvider);
      ref.invalidate(myClubApplicationsProvider);
    }
    if (rooms) {
      ref.invalidate(chatRoomProvider);
      ref.invalidate(chatAccessProvider);
    }
    if (update.reconnected) ref.invalidate(chatMessagesProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(clubLiveUpdatesProvider, (_, next) {
      final update = next.asData?.value;
      if (update != null) _refresh(update);
    });
    return widget.child;
  }
}
