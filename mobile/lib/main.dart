import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/strivo_app.dart';
import 'core/config/app_config.dart';
import 'core/services/audit_service.dart';
import 'core/services/content_service.dart';
import 'core/services/invitation_service.dart';
import 'core/services/log_service.dart';
import 'core/services/membership_service.dart';
import 'core/services/student_service.dart';

Future<void> main() async {
  await AppLog.init();
  AppLog.installGlobalHandlers();

  // runZonedGuarded is the backstop: it catches errors raised from timers and
  // async callbacks that neither FlutterError.onError nor the platform
  // dispatcher see.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (AppConfig.supabaseConfigured) {
        try {
          await Supabase.initialize(
            url: AppConfig.supabaseUrl,
            // Supabase renamed the anon key to the publishable key. The
            // build-time define stays SUPABASE_ANON_KEY so the Dockerfile and
            // .env contract is unchanged.
            publishableKey: AppConfig.supabaseAnonKey,
          );
          final client = Supabase.instance.client;
          // Every service that talks to Supabase needs the client handed to
          // it explicitly; they are plain statics rather than providers so
          // that they can be called from callbacks and guards.
          AuditService.attach(client);
          InvitationService.attach(client);
          MembershipService.attach(client);
          StudentService.attach(client);
          ContentService.attach(client);
          AppLog.info('supabase.ready');
        } catch (error, stackTrace) {
          AppLog.error('supabase.init_failed', error, stackTrace);
        }
      } else {
        AppLog.warn('supabase.not_configured',
            detail:
                'SUPABASE_URL and SUPABASE_ANON_KEY were not supplied at build time');
      }

      runApp(const ProviderScope(child: StrivoApp()));
    },
    (error, stackTrace) {
      AppLog.error('zone.error', error, stackTrace);
    },
  );
}
