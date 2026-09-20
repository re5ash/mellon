import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/help_repository.dart';
import '../domain/help_request.dart';

class SupabaseHelpRequestRepository implements HelpRequestRepository {
  SupabaseHelpRequestRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<HelpRequest>> list({String? parishId}) async {
    var query = client
        .from('help_requests')
        .select('id,title,description,created_at')
        .eq('status', 'published');
    if (parishId != null) query = query.eq('parish_id', parishId);
    final rows = await query.order('created_at').order('id').limit(30);
    return rows.map(HelpRequest.fromJson).toList(growable: false);
  }
}
