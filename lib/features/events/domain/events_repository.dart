import 'event.dart';

abstract interface class ParishEventRepository {
  Future<List<ParishEvent>> list({String? parishId});
}
