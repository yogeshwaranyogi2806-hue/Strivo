import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!AppConfig.supabaseConfigured) return null;
  return Supabase.instance.client;
});