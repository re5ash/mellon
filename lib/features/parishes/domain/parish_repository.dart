import 'parish.dart';

abstract interface class ParishRepository {
  Future<List<Parish>> list({String query = '', int offset = 0});
  Future<Parish> get(String id);
}
