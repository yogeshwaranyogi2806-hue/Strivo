import 'package:supabase_flutter/supabase_flutter.dart';

import 'log_service.dart';

/// A role a person holds inside one studio. Mirrors the check constraint on
/// public.organization_memberships.
enum OrgRole {
  owner('owner', 'Admin', rank: 0),
  coach('coach', 'Coach', rank: 1),
  student('student', 'Student', rank: 2),
  parent('parent', 'Parent', rank: 3);

  const OrgRole(this.value, this.label, {required this.rank});

  final String value;
  final String label;

  /// Lower rank means broader access. Used to pick the strongest role when one
  /// person belongs to more than one studio.
  final int rank;

  /// Admin and coach both work in the back office. Students and parents are
  /// front office. This is the split that decides which dashboard someone sees.
  bool get isStaff => this == OrgRole.owner || this == OrgRole.coach;

  bool get isFrontOffice => this == OrgRole.student || this == OrgRole.parent;

  static OrgRole fromValue(String? value) => OrgRole.values.firstWhere(
        (r) => r.value == value,
        // An unrecognised role must not be treated as staff. Defaulting upward
        // would hand out back-office access on a typo.
        orElse: () => OrgRole.parent,
      );
}

/// One studio this person belongs to.
class Membership {
  const Membership({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.role,
  });

  /// This membership row's own id. Rows in leaves, payments, task_submissions
  /// and contents are keyed by it, so writes need it.
  final String id;
  final String organizationId;
  final String organizationName;
  final OrgRole role;

  factory Membership.fromRow(Map<String, dynamic> row) {
    final organization = row['organizations'] as Map<String, dynamic>?;
    return Membership(
      id: row['id'] as String? ?? '',
      organizationId: row['organization_id'] as String? ?? '',
      organizationName: organization?['name'] as String? ?? 'this studio',
      role: OrgRole.fromValue(row['role'] as String?),
    );
  }
}

class MembershipException implements Exception {
  MembershipException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads who the signed-in person is and what they may reach.
abstract final class MembershipService {
  static SupabaseClient? _client;

  static void attach(SupabaseClient client) {
    _client = client;
  }

  /// Every membership belonging to the current user, strongest first. Empty
  /// when signed out or when the account has not joined a studio yet.
  static Future<List<Membership>> current() async {
    final client = _client;
    if (client == null) {
      throw MembershipException('Connect your Strivo workspace to continue.');
    }
    if (client.auth.currentSession == null) return const [];

    try {
      final rows = await client.from('organization_memberships').select(
            'id, organization_id, role, organizations(id, name)',
          );
      final memberships = rows
          .map<Membership>((row) => Membership.fromRow(row))
          .where((m) => m.organizationId.isNotEmpty && m.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.role.rank.compareTo(b.role.rank));
      AppLog.info('membership.loaded', detail: 'count=${memberships.length}');
      return memberships;
    } catch (error, stackTrace) {
      AppLog.error('membership.load_failed', error, stackTrace);
      throw MembershipException(
        'Could not load your account. Please try again.',
      );
    }
  }

  /// The role that decides the dashboard: the strongest membership, if any.
  /// Null means the account belongs to no studio, which is a real state during
  /// first-admin bootstrap and must be handled rather than assumed away.
  static OrgRole? primaryRole(List<Membership> memberships) =>
      memberships.isEmpty ? null : memberships.first.role;

  /// True when this person should be routed to the back office. An account with
  /// no membership is not staff: it has nothing to administer yet.
  static bool isBackOffice(List<Membership> memberships) =>
      primaryRole(memberships)?.isStaff ?? false;

  /// True when the person is signed in but has not joined a studio yet.
  static bool needsWorkspace(List<Membership> memberships) =>
      memberships.isEmpty;

  /// Where a person should land after signing in.
  static String landingRoute(List<Membership> memberships) {
    if (needsWorkspace(memberships)) return '/no-workspace';
    return isBackOffice(memberships) ? '/home' : '/student';
  }

  /// True only while the deployment has no admin at all, which is the single
  /// moment self-service studio creation is safe. Once a coach exists this goes
  /// false for good, so nobody can spin up a rival studio to phish students
  /// away from the real one.
  static Future<bool> deploymentNeedsBootstrap() async {
    final client = _client;
    if (client == null) return false;
    try {
      return await client.rpc('deployment_needs_bootstrap') as bool;
    } catch (error, stackTrace) {
      // If this is missing the database has not been migrated yet; do not offer
      // a button that cannot work.
      AppLog.error('membership.bootstrap_check_failed', error, stackTrace);
      return false;
    }
  }

  /// Creates the first studio and makes the caller its owner. Only reachable
  /// while [deploymentNeedsBootstrap] is true.
  static Future<String> createFirstWorkspace(String name) async {
    final client = _client;
    if (client == null) {
      throw MembershipException('Connect your Strivo workspace to continue.');
    }
    try {
      final id = await client.rpc(
        'create_coach_workspace',
        params: {'workspace_name': name.trim()},
      );
      AppLog.info('membership.workspace_bootstrapped');
      return id as String;
    } catch (error, stackTrace) {
      AppLog.error('membership.workspace_bootstrap_failed', error, stackTrace);
      throw MembershipException(_readable(error));
    }
  }

  /// Postgres raises plain English, but PostgREST wraps them in a code and the
  /// client prefixes its own class name. Map the few cases a person would not
  /// understand and keep the rest generic rather than leaking internals.
  static String _readable(Object error) {
    final message = error.toString();
    if (message.contains('Authentication required')) {
      return 'Please sign in again and try once more.';
    }
    if (message.contains('duplicate key')) {
      return 'That name is already taken. Try another.';
    }
    return 'Could not create the studio. Please try again.';
  }
}
