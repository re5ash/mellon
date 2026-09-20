import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

final configProvider = Provider<AppConfig>(
  (ref) => throw StateError('Override at bootstrap'),
);
final backendProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
