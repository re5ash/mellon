import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/event.dart';
import '../domain/events_repository.dart';

class SupabaseParishEventRepository implements ParishEventRepository {
  SupabaseParishEventRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<ParishEvent>> list({String? parishId}) async {
    var query = client
        .from('events')
        .select()
        .eq('status', 'published')
        .gte('ends_at', DateTime.now().toUtc().toIso8601String());
    if (parishId != null) query = query.eq('parish_id', parishId);
    final rows = await query.order('starts_at').order('id').limit(30);
    return rows.map(ParishEvent.fromJson).toList(growable: false);
  }
}
