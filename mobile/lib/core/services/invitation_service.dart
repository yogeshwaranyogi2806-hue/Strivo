import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'audit_service.dart';
import 'log_service.dart';

enum InviteRole {
  owner('owner', 'Admin'),
  coach('coach', 'Coach'),
  student('student', 'Student');

  const InviteRole(this.value, this.label);

  final String value;
  final String label;

  static InviteRole fromValue(String? value) => InviteRole.values
      .firstWhere((r) => r.value == value, orElse: () => InviteRole.student);
}

/// What a code turns out to be, shown before the person commits to signing up.
class InvitationPreview {
  const InvitationPreview({
    required this.role,
    required this.organizationName,
    required this.invitedEmail,
    required this.isUsable,
  });

  final InviteRole role;
  final String organizationName;
  final String? invitedEmail;
  final bool isUsable;

  /// True when this code can be redeemed by whoever is signing up. A code issued
  /// to a specific mailbox can only be redeemed by that mailbox.
  bool get openToAnyone => invitedEmail == null || invitedEmail!.isEmpty;

  factory InvitationPreview.fromRow(Map<String, dynamic> row) =>
      InvitationPreview(
        role: InviteRole.fromValue(row['role'] as String?),
        organizationName:
            (row['organization_name'] as String?) ?? 'this studio',
        invitedEmail: row['invited_email'] as String?,
        isUsable: row['is_usable'] as bool? ?? false,
      );
}

class InvitationException implements Exception {
  InvitationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Wraps the V9 invitation functions.
abstract final class InvitationService {
  static SupabaseClient? _client;

  /// Set when the Supabase project requires email confirmation, so the person
  /// has a login but no session yet. Remembered until they sign in and the
  /// invitation can finally be redeemed.
  static String? _pendingToken;

  static String? get pendingToken => _pendingToken;

  static void attach(SupabaseClient client) {
    _client = client;
  }

  static void rememberPending(String token) {
    _pendingToken = normaliseCode(token);
  }

  static void clearPending() {
    _pendingToken = null;
  }

  /// Called after a successful sign-in. Redeems a waiting invitation, if any.
  /// Returns an error message if redemption failed, otherwise null.
  static Future<String?> redeemPendingIfAny() async {
    final token = _pendingToken;
    if (token == null) return null;
    try {
      await accept(token);
      clearPending();
      return null;
    } on InvitationException catch (error) {
      clearPending();
      return error.message;
    }
  }

  /// Accepts a bare code, a grouped code, or a pasted invite link, in any
  /// casing. A link contributes only its last segment, so the domain is not
  /// mistaken for part of the code.
  static String normaliseCode(String raw) {
    var value = raw.trim();
    if (value.contains('/')) {
      final segments = value.split('/').where((part) => part.isNotEmpty);
      if (segments.isNotEmpty) value = segments.last;
    }
    return value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  }

  /// Groups a token for reading aloud or squinting at: A1B2 C3D4 E5F6 7890.
  static String formatCode(String token) {
    final buffer = StringBuffer();
    for (var i = 0; i < token.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(token.substring(i, (i + 4).clamp(0, token.length)));
    }
    return buffer.toString();
  }

  static String shareLink(String token) => 'https://strivo.app/invite/$token';

  /// Checks a code. Callable while signed out, because nobody has an account yet.
  static Future<InvitationPreview> lookup(String raw) async {
    final client = _client;
    if (client == null) {
      throw InvitationException('Connect your Strivo workspace to continue.');
    }
    final token = normaliseCode(raw);
    if (token.length < 16) {
      throw InvitationException('That does not look like an invitation code.');
    }
    try {
      final rows = await client.rpc(
        'invitation_details',
        params: <String, Object?>{'p_token': token},
      );
      if (rows.isEmpty) {
        throw InvitationException('That invitation code is not valid.');
      }
      final preview = InvitationPreview.fromRow(rows.first);
      if (!preview.isUsable) {
        throw InvitationException(
            'That invitation has already been used or has expired.');
      }
      return preview;
    } on InvitationException {
      rethrow;
    } catch (error) {
      AppLog.error('invitation.lookup_failed', error, StackTrace.current,
          detail: token);
      throw InvitationException(_messageFrom(error));
    }
  }

  static Future<String> create({
    required InviteRole role,
    String? email,
    String? fullName,
    int expiresDays = 14,
  }) async {
    final client = _client;
    if (client == null) {
      throw InvitationException('Connect your Strivo workspace to continue.');
    }
    try {
      final token = await client.rpc(
        'create_invitation',
        params: <String, Object?>{
          'p_role': role.value,
          'p_email':
              email == null || email.trim().isEmpty ? null : email.trim(),
          'p_full_name': fullName == null || fullName.trim().isEmpty
              ? null
              : fullName.trim(),
          'p_expires_days': expiresDays,
        },
      );
      final code = token as String;
      AuditService.record('invitation.created', detail: 'role=${role.value}');
      return code;
    } catch (error) {
      AppLog.error('invitation.create_failed', error, StackTrace.current,
          detail: role.value);
      throw InvitationException(_messageFrom(error));
    }
  }

  /// Redeems a code. Call this only after the person has created their login.
  static Future<String> accept(String raw) async {
    final client = _client;
    if (client == null) {
      throw InvitationException('Connect your Strivo workspace to continue.');
    }
    final token = normaliseCode(raw);
    try {
      final organizationId = await client.rpc(
        'accept_invitation',
        params: <String, Object?>{'p_token': token},
      );
      AuditService.record('invitation.accepted',
          detail: 'organization=$organizationId');
      return organizationId as String;
    } catch (error) {
      AppLog.error('invitation.accept_failed', error, StackTrace.current,
          detail: token);
      throw InvitationException(_messageFrom(error));
    }
  }

  /// Pulls the server's message out of a PostgrestException, which is where the
  /// useful text lives ("That invitation has already been used"). Falls back to
  /// something neutral rather than leaking internals to the screen.
  static String _messageFrom(Object error) {
    final match = RegExp(r'message:\s*([^,]+)').firstMatch(error.toString());
    final message = match?.group(1)?.trim();
    if (message == null || message.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return message;
  }
}
