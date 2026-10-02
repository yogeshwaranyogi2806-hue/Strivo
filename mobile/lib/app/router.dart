import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/providers.dart';
import '../core/services/log_service.dart';
import '../core/services/membership_service.dart';
import '../app/theme.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/sign_up_page.dart';
import '../features/back_office/presentation/coach_home_page.dart';
import '../features/back_office/presentation/content_manage_page.dart';
import '../features/back_office/presentation/invite_page.dart';
import '../features/back_office/presentation/student_links_page.dart';
import '../features/front_office/presentation/content_library_page.dart';
import '../features/front_office/presentation/no_workspace_page.dart';
import '../features/front_office/presentation/redeem_invite_page.dart';
import '../features/front_office/presentation/student_home_page.dart';
import '../shared/diagnostics/log_viewer_page.dart';

/// Owns the auth session and the signed-in person's memberships, and notifies
/// go_router whenever either changes.
///
/// The two used to be separate and the role load never notified, so after
/// signing in the redirect ran once with no role known and was never re-evaluated
/// once the role arrived. Owning both in one place makes it impossible to
/// forget the second notify.
class _SessionWatcher extends ChangeNotifier {
  _SessionWatcher(this._client) {
    _subscription = _client.auth.onAuthStateChange.listen((_) => _refresh());
    _refresh();
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;

  /// Null means "not known yet". The redirect holds on the loading screen rather
  /// than guessing a dashboard.
  List<Membership>? _memberships;

  List<Membership>? get memberships => _memberships;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_client.auth.currentSession == null) {
      // Drop the role so the next sign-in re-resolves it rather than reusing
      // the previous person's.
      _memberships = null;
      notifyListeners();
      return;
    }
    if (_memberships != null) {
      notifyListeners();
      return;
    }
    // Notify while the role is still unknown so the redirect can send the person
    // to the loading screen immediately rather than showing a stale dashboard.
    notifyListeners();
    try {
      _memberships = await MembershipService.current();
    } catch (error, stackTrace) {
      AppLog.error('router.role_load_failed', error, stackTrace);
      // A failed read is treated as "no membership" so the person lands on the
      // no-workspace screen and can retry, rather than being bounced to login.
      _memberships = const [];
    }
    notifyListeners();
  }
}

/// Every path the app actually serves. Anything else is a stale or unexpected
/// link and is sent somewhere useful instead of showing go_router's
/// "Page not found".
const Set<String> _knownRoutes = {
  '/login',
  '/signup',
  '/redeem',
  '/resolving',
  '/no-workspace',
  '/home',
  '/student',
  '/logs',
  '/invite',
  '/content',
  '/student-records',
  '/library',
};

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider)!;
  final session = _SessionWatcher(client);
  ref.onDispose(session.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: session,
    errorBuilder: (context, state) => const _UnknownRoutePage(),
    redirect: (context, state) {
      final location = state.matchedLocation;

      final signedIn = client.auth.currentSession != null;
      if (!signedIn) {
        if (location != '/login' && location != '/signup') return '/login';
        return null;
      }

      // /signup is deliberately not redirected away once signed in: the page
      // still has to redeem an invitation, and it needs to stay mounted to
      // report a failure. It navigates home itself when it is done.
      if (location == '/signup' || location == '/logs') return null;

      // A signed-in person with no studio uses this to attach their account. It
      // must stay reachable while they have no membership, otherwise the
      // no-workspace redirect below would lock them out of it.
      if (location == '/redeem') return null;

      // The library is reachable from either side; a coach previewing what a
      // student sees lands here too.
      if (location == '/library') return null;
      if (location == '/login') {
        final known = session.memberships;
        // Until the role lands, stay put rather than flashing the wrong app.
        if (known == null) return null;
        return MembershipService.landingRoute(known);
      }

      final known = session.memberships;
      // Role unknown: hold on a loading screen instead of guessing a dashboard.
      if (known == null) return '/resolving';
      if (MembershipService.needsWorkspace(known)) {
        return location == '/no-workspace' ? null : '/no-workspace';
      }

      final staff = MembershipService.isBackOffice(known);
      if (staff) {
        // A student must not reach back-office pages by typing the URL. The
        // database would refuse the queries anyway; this keeps the UI honest.
        if (location == '/student' ||
            location == '/content' ||
            location == '/student-records') {
          return '/home';
        }
      } else if (location == '/home') {
        return '/student';
      }

      // An unrecognised path is almost always a link that came from somewhere
      // else: a Supabase confirmation redirect, an old bookmark, a stale invite
      // URL. Send the person to the app instead of go_router's error page.
      if (!_knownRoutes.contains(location)) {
        return MembershipService.landingRoute(known);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: '/resolving',
        builder: (context, state) => const _ResolvingPage(),
      ),
      GoRoute(
        path: '/no-workspace',
        builder: (context, state) => const NoWorkspacePage(),
      ),
      GoRoute(
        path: '/redeem',
        builder: (context, state) => const RedeemInvitePage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const CoachHomePage(),
      ),
      GoRoute(
        path: '/student',
        builder: (context, state) => const StudentHomePage(),
      ),
      GoRoute(
        path: '/logs',
        builder: (context, state) => const LogViewerPage(),
      ),
      GoRoute(
        path: '/invite',
        builder: (context, state) => const InvitePage(),
      ),
      GoRoute(
        path: '/content',
        builder: (context, state) => const ContentManagePage(),
      ),
      GoRoute(
        path: '/student-records',
        builder: (context, state) => const StudentLinksPage(),
      ),
      GoRoute(
        path: '/library',
        builder: (context, state) => const ContentLibraryPage(),
      ),

      // Catch-all, registered last so every explicit route above wins. Supabase
      // redirects people to paths this app never defined (and a stray fragment
      // such as /#sb is harmless because routing ignores fragments). Without
      // this, any unexpected path renders go_router's "Page not found".
      GoRoute(
        path: '/:rest',
        builder: (context, state) => const _UnknownRoutePage(),
      ),
    ],
  );
});

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 36, color: StrivoColors.muted),
              const SizedBox(height: 14),
              Text('That link is not valid',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'It may be old, or it may belong to a different studio.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go('/login'),
                child: const Text('Go to Strivo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown for the moment between "signed in" and "role known". Without this the
/// router would either flash the wrong dashboard or bounce to login.
class _ResolvingPage extends StatelessWidget {
  const _ResolvingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
