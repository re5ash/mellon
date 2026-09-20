import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/parish.dart';
import '../domain/parish_repository.dart';

class SupabaseParishRepository implements ParishRepository {
  SupabaseParishRepository(this.client);
  final SupabaseClient client;
  static const fields = 'id,name,address,description,latitude,longitude';
  @override
  Future<List<Parish>> list({String query = '', int offset = 0}) async {
    var request = client.from('parishes').select(fields);
    if (query.trim().isNotEmpty)
      request = request.ilike(
        'name',
        '%${query.trim().replaceAll('%', r'\%').replaceAll('_', r'\_')}%',
      );
    final rows = await request
        .order('name')
        .order('id')
        .range(offset, offset + 29);
    return rows.map(Parish.fromJson).toList(growable: false);
  }

  @override
  Future<Parish> get(String id) async => Parish.fromJson(
    await client.from('parishes').select(fields).eq('id', id).single(),
  );
}
