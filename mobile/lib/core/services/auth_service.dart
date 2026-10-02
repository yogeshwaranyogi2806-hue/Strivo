import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'audit_service.dart';
import 'log_service.dart';

/// Sign-out lives in its own place because both sides of the app need it and
/// neither owns the Supabase client. Until this existed the only way out of a
/// session was to clear site data, which on a shared device logs out everyone.
abstract final class AuthService {
  /// Ends the session. Safe to call when already signed out, so a button can
  /// fire without first checking. Returns false only if the client is missing.
  static Future<bool> signOut() async {
    if (!AppConfig.supabaseConfigured) return false;
    try {
      await Supabase.instance.client.auth.signOut();
      AppLog.info('auth.sign_out');
      AuditService.record('auth.signed_out');
      return true;
    } catch (error, stackTrace) {
      AppLog.error('auth.sign_out_failed', error, stackTrace);
      return false;
    }
  }

  /// Signs out and returns to the login screen. Used by every "use a different
  /// account" affordance.
  ///
  /// The navigation is deliberately not left to the caller: simply navigating
  /// to /login while a session is still active makes the router send the user
  /// straight back to the dashboard they were trying to leave.
  static Future<bool> signOutAndReturnToLogin(
      VoidCallback navigateToLogin) async {
    final done = await signOut();
    navigateToLogin();
    return done;
  }
}
