import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'log_service.dart';

/// Writes business actions to two places: the local log file (always) and the
/// `audit_log` table (best effort).
///
/// The database write is deliberately fire-and-forget. If the V8 migration has
/// not been applied yet, or the device is offline, the local file still holds
/// the entry — so a failed sync is never worth interrupting the user for.
abstract final class AuditService {
  static SupabaseClient? _client;

  static void attach(SupabaseClient client) {
    _client = client;
  }

  /// Records that a person did something worth remembering later.
  ///
  /// Use stable, machine-readable event names: `student.added`, not "added a
  /// student". These names become the audit vocabulary.
  static void record(String event, {String? detail}) {
    AppLog.action(event, detail: detail);
    unawaited(_sync(event, detail));
  }

  static Future<void> _sync(String event, String? detail) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('record_audit_event', params: <String, Object?>{
        'p_event': event,
        'p_detail':
            detail == null ? null : <String, Object?>{'summary': detail},
        'p_session': AppLog.sessionId,
      });
    } catch (_) {
      AppLog.debug('audit.sync_failed', detail: event);
    }
  }
}
