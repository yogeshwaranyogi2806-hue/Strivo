import 'package:supabase_flutter/supabase_flutter.dart';

import 'audit_service.dart';
import 'log_service.dart';
import 'membership_service.dart';

/// A piece of published material a student can open.
class ContentItem {
  const ContentItem({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    required this.isPublished,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String description;
  final ContentType type;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final bool isPublished;
  final DateTime? publishedAt;

  bool get hasFile => fileUrl != null && fileUrl!.isNotEmpty;

  factory ContentItem.fromRow(Map<String, dynamic> row) => ContentItem(
        id: row['id'] as String? ?? '',
        title: row['title'] as String? ?? 'Untitled',
        description: row['description'] as String? ?? '',
        type: ContentType.fromValue(row['content_type'] as String?),
        fileUrl: row['file_url'] as String?,
        fileName: row['file_name'] as String?,
        fileSize: row['file_size'] as int?,
        isPublished: row['is_published'] as bool? ?? false,
        publishedAt: _parse(row['published_at']),
      );

  static DateTime? _parse(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

enum ContentType {
  article('article', 'Article'),
  video('video', 'Video'),
  document('document', 'Document'),
  image('image', 'Image');

  const ContentType(this.value, this.label);

  final String value;
  final String label;

  static ContentType fromValue(String? value) => ContentType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => ContentType.article,
      );
}

/// One side of an unlinked student: either a student record with no login, or a
/// student login with no record.
class UnlinkedStudent {
  const UnlinkedStudent({
    required this.studentId,
    required this.studentName,
    required this.membershipId,
    required this.loginEmail,
  });

  /// Null on the login side of the pair.
  final String? studentId;
  final String? studentName;

  /// Null on the record side of the pair.
  final String? membershipId;
  final String? loginEmail;

  bool get isRecord => studentId != null;
  bool get isLogin => membershipId != null;

  String get label =>
      isRecord ? studentName ?? 'Unnamed' : loginEmail ?? 'Unknown';
}

class ContentException implements Exception {
  ContentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the content library. Students only ever see published items; the
/// database enforces that independently of anything decided here.
abstract final class ContentService {
  static SupabaseClient? _client;

  static void attach(SupabaseClient client) {
    _client = client;
  }

  static SupabaseClient get _require {
    final client = _client;
    if (client == null) {
      throw ContentException('Connect your Strivo workspace to continue.');
    }
    if (client.auth.currentSession == null) {
      throw ContentException('Please sign in again.');
    }
    return client;
  }

  /// The studio the caller belongs to. Content is always scoped to one studio.
  static Future<String> _organizationId() async {
    final memberships = await MembershipService.current();
    if (memberships.isEmpty) {
      throw ContentException('You are not part of a studio yet.');
    }
    return memberships.first.organizationId;
  }

  static Future<List<ContentItem>> publishedLibrary() async {
    final client = _require;
    final organizationId = await _organizationId();
    final rows = await client
        .from('contents')
        .select('id, title, description, content_type, file_url, file_name, '
            'file_size, is_published, published_at')
        .eq('organization_id', organizationId)
        .eq('is_published', true)
        .order('published_at', ascending: false);
    return rows.map(ContentItem.fromRow).toList();
  }

  /// Everything the studio has, published or not. Coaches only.
  static Future<List<ContentItem>> allForCoach() async {
    final client = _require;
    final organizationId = await _organizationId();
    final rows = await client
        .from('contents')
        .select('id, title, description, content_type, file_url, file_name, '
            'file_size, is_published, published_at')
        .eq('organization_id', organizationId)
        .order('created_at', ascending: false);
    return rows.map(ContentItem.fromRow).toList();
  }

  static Future<ContentItem> create({
    required String title,
    required String description,
    required ContentType type,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    bool publish = true,
  }) async {
    final client = _require;
    final organizationId = await _organizationId();
    final memberships = await MembershipService.current();
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ContentException('Give the item a title.');
    }
    try {
      final id = await client
          .from('contents')
          .insert(<String, Object?>{
            'organization_id': organizationId,
            'uploaded_by': memberships.first.id,
            'title': trimmedTitle,
            'description': description.trim(),
            'content_type': type.value,
            'file_url': fileUrl,
            'file_name': fileName,
            'file_size': fileSize,
            'is_published': publish,
            'published_at':
                publish ? DateTime.now().toUtc().toIso8601String() : null,
          })
          .select('id')
          .single();
      AuditService.record('content.created', detail: 'type=${type.value}');
      return ContentItem(
        id: id['id'] as String,
        title: trimmedTitle,
        description: description.trim(),
        type: type,
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        isPublished: publish,
        publishedAt: DateTime.now(),
      );
    } catch (error, stackTrace) {
      AppLog.error('content.create_failed', error, stackTrace);
      throw ContentException('Could not save that item. Please try again.');
    }
  }

  /// Publishing or unpublishing. published_at is set the first time an item
  /// goes live and left alone afterwards, so the library keeps its order.
  static Future<void> setPublished(String id, bool published) async {
    final client = _require;
    try {
      await client.from('contents').update(<String, Object?>{
        'is_published': published,
        if (published) 'published_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      AuditService.record('content.publish_changed',
          detail: 'id=$id published=$published');
    } catch (error, stackTrace) {
      AppLog.error('content.publish_failed', error, stackTrace);
      throw ContentException('Could not change that item.');
    }
  }

  static Future<void> delete(String id) async {
    final client = _require;
    try {
      await client.from('contents').delete().eq('id', id);
      AuditService.record('content.deleted');
    } catch (error, stackTrace) {
      AppLog.error('content.delete_failed', error, stackTrace);
      throw ContentException('Could not delete that item.');
    }
  }

  /// Both halves of an unlinked student, so a coach can match them by eye.
  static Future<List<UnlinkedStudent>> unlinkedStudents() async {
    final client = _require;
    try {
      final rows = await client.rpc('unlinked_student_records');
      return rows.map((row) {
        return UnlinkedStudent(
          studentId: row['student_id'] as String?,
          studentName: row['student_name'] as String?,
          membershipId: row['membership_id'] as String?,
          loginEmail: row['student_email'] as String?,
        );
      }).toList();
    } catch (error, stackTrace) {
      AppLog.error('students.unlinked_load_failed', error, stackTrace);
      throw ContentException('Could not load the student list.');
    }
  }

  /// Attaches a login to a student record by hand. Used when the automatic
  /// name match in accept_invitation was wrong or refused as ambiguous.
  static Future<void> linkStudent({
    required String studentId,
    required String membershipId,
  }) async {
    final client = _require;
    try {
      await client.rpc('link_student_record', params: <String, Object?>{
        'p_student_id': studentId,
        'p_membership_id': membershipId,
      });
      AuditService.record('student.record_linked');
    } catch (error, stackTrace) {
      AppLog.error('students.link_failed', error, stackTrace);
      throw ContentException(_messageFrom(error));
    }
  }

  static String _messageFrom(Object error) {
    final match = RegExp(r'message:\s*([^,]+)').firstMatch(error.toString());
    final message = match?.group(1)?.trim();
    return message == null || message.isEmpty
        ? 'Could not link those two.'
        : message;
  }
}
