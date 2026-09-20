import 'help_request.dart';

abstract interface class HelpRequestRepository {
  Future<List<HelpRequest>> list({String? parishId});
}
