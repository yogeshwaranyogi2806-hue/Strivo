import 'package:flutter_test/flutter_test.dart';
import 'package:strivo/core/config/app_config.dart';

void main() {
  test('Supabase stays disabled when build values are absent', () {
    expect(AppConfig.supabaseUrl, isEmpty);
    expect(AppConfig.supabaseAnonKey, isEmpty);
    expect(AppConfig.supabaseConfigured, isFalse);
  });
}
