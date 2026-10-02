import 'package:supabase_flutter/supabase_flutter.dart';

import 'audit_service.dart';
import 'log_service.dart';

/// The signed-in student's own identity: which studio, which membership row,
/// which student row. Every write in this service needs all three, because
/// leaves, submissions and payments are each keyed by (organization_id,
/// student_id, membership_id) and the database rejects a mismatch.
class StudentIdentity {
  const StudentIdentity({
    required this.organizationId,
    required this.membershipId,
    required this.studentId,
    required this.fullName,
  });

  final String organizationId;
  final String membershipId;
  final String studentId;
  final String fullName;
}

class StudentException implements Exception {
  StudentException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum LeaveStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const LeaveStatus(this.value);

  final String value;

  String get label => switch (this) {
        LeaveStatus.pending => 'Awaiting review',
        LeaveStatus.approved => 'Approved',
        LeaveStatus.rejected => 'Not approved',
      };

  static LeaveStatus fromValue(String? value) => LeaveStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => LeaveStatus.pending,
      );
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.reviewNote,
  });

  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final LeaveStatus status;
  final String reviewNote;

  int get dayCount =>
      endDate
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays +
      1;
}

/// A task, plus this student's submission of it if one exists.
class TaskWithSubmission {
  const TaskWithSubmission({required this.task, this.submission});

  final Map<String, dynamic> task;
  final Map<String, dynamic>? submission;

  String get title => task['title'] as String? ?? 'Untitled';
  String? get dueDate => task['due_date'] as String?;
  String? get classId => task['class_id'] as String?;
  bool get isSubmitted => submission != null;

  bool get isOverdue {
    final due = dueDate;
    if (due == null || isSubmitted) return false;
    final parsed = DateTime.tryParse(due);
    if (parsed == null) return false;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day).isAfter(parsed);
  }

  int? get daysUntilDue {
    final due = dueDate;
    if (due == null) return null;
    final parsed = DateTime.tryParse(due);
    if (parsed == null) return null;
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    return parsed.difference(midnight).inDays;
  }
}

class PaymentRecord {
  const PaymentRecord({
    required this.amount,
    required this.status,
    required this.method,
    required this.paidAt,
    required this.dueDate,
    required this.feeName,
  });

  /// numeric(10,2) arrives from PostgREST as num, sometimes as int.
  final num amount;
  final String status;
  final String method;
  final DateTime? paidAt;
  final DateTime? dueDate;
  final String feeName;

  bool get isOutstanding => status == 'pending' || status == 'failed';
}

/// Reads and writes the signed-in student's own records. Every query here is
/// additionally constrained by row level security, so a bug in this file cannot
/// widen what the person can see; the policies in V10 are the real boundary.
abstract final class StudentService {
  static SupabaseClient? _client;

  static void attach(SupabaseClient client) {
    _client = client;
  }

  static SupabaseClient get _require {
    final client = _client;
    if (client == null) {
      throw StudentException('Connect your Strivo workspace to continue.');
    }
    if (client.auth.currentSession == null) {
      throw StudentException('Please sign in again.');
    }
    return client;
  }

  /// Resolves the caller's membership and student rows. Throws when the account
  /// has no student record, which means the link was never made.
  static Future<StudentIdentity> identity() async {
    final client = _require;
    final userId = client.auth.currentUser!.id;

    final memberships = await client
        .from('organization_memberships')
        .select('id, organization_id')
        .eq('user_id', userId)
        .eq('role', 'student')
        .limit(1);

    if (memberships.isEmpty) {
      throw StudentException('Your student account is not set up yet.');
    }
    final membership = memberships.first;
    final organizationId = membership['organization_id'] as String;
    final membershipId = membership['id'] as String;

    final students = await client
        .from('students')
        .select('id, full_name')
        .eq('organization_id', organizationId)
        .eq('membership_id', membershipId)
        .limit(1);

    if (students.isEmpty) {
      throw StudentException(
        'Your studio has not linked your login to a student record yet. '
        'Ask your coach to check this.',
      );
    }

    final identity = StudentIdentity(
      organizationId: organizationId,
      membershipId: membershipId,
      studentId: students.first['id'] as String,
      fullName: students.first['full_name'] as String? ?? 'Student',
    );
    AppLog.info('student.identity_resolved', detail: 'org=$organizationId');
    return identity;
  }

  static Future<List<Map<String, dynamic>>> announcements(
      StudentIdentity me) async {
    final client = _require;
    final rows = await client
        .from('announcements')
        .select('id, title, body, priority, published_at')
        .eq('organization_id', me.organizationId)
        .eq('is_published', true)
        .order('published_at', ascending: false)
        .limit(10);
    return rows;
  }

  /// Tasks for every class this student is enrolled in, with this student's own
  /// submission attached where one exists.
  static Future<List<TaskWithSubmission>> tasks(StudentIdentity me) async {
    final client = _require;

    final classIds = await client
        .from('class_enrollments')
        .select('class_id')
        .eq('organization_id', me.organizationId)
        .eq('student_id', me.studentId);

    final ids = classIds
        .map((row) => row['class_id'] as String?)
        .whereType<String>()
        .toSet();

    if (ids.isEmpty) return [];

    final taskRows = await client
        .from('tasks')
        .select('id, class_id, title, description, due_date')
        .eq('organization_id', me.organizationId)
        .eq('is_active', true)
        .inFilter('class_id', ids.toList())
        .order('due_date', ascending: true);

    final submissions = await client
        .from('task_submissions')
        .select(
            'id, task_id, submission_text, submitted_at, rating, review_note')
        .eq('organization_id', me.organizationId)
        .eq('student_id', me.studentId);

    final byTask = <String, Map<String, dynamic>>{
      for (final row in submissions)
        if (row['task_id'] is String) row['task_id'] as String: row,
    };

    return taskRows
        .map((task) => TaskWithSubmission(
              task: task,
              submission: byTask[task['id']],
            ))
        .toList();
  }

  /// Records the student's work against a task. One row per task per student is
  /// enforced by the unique constraint, so this is an upsert rather than an
  /// insert: re-submitting replaces the earlier answer.
  static Future<void> submitTask({
    required StudentIdentity me,
    required String taskId,
    required String answer,
  }) async {
    final client = _require;
    final trimmed = answer.trim();
    if (trimmed.isEmpty) {
      throw StudentException('Write something before submitting.');
    }
    try {
      await client.from('task_submissions').upsert(<String, Object?>{
        'organization_id': me.organizationId,
        'task_id': taskId,
        'student_id': me.studentId,
        'membership_id': me.membershipId,
        'submission_text': trimmed,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'organization_id,task_id,student_id');
      AuditService.record('student.task_submitted');
    } catch (error, stackTrace) {
      AppLog.error('student.task_submit_failed', error, stackTrace);
      throw StudentException('Could not submit your work. Please try again.');
    }
  }

  static Future<List<LeaveRequest>> leaves(StudentIdentity me) async {
    final client = _require;
    final rows = await client
        .from('leaves')
        .select('id, start_date, end_date, reason, status, review_note')
        .eq('organization_id', me.organizationId)
        .eq('membership_id', me.membershipId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map((row) {
      return LeaveRequest(
        id: row['id'] as String,
        startDate: DateTime.parse(row['start_date'] as String),
        endDate: DateTime.parse(row['end_date'] as String),
        reason: row['reason'] as String? ?? '',
        status: LeaveStatus.fromValue(row['status'] as String?),
        reviewNote: row['review_note'] as String? ?? '',
      );
    }).toList();
  }

  static Future<void> applyForLeave({
    required StudentIdentity me,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    final client = _require;
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    if (end.isBefore(start)) {
      throw StudentException('The last day cannot be before the first day.');
    }
    if (start.isBefore(midnight)) {
      throw StudentException('Leave cannot start in the past.');
    }
    try {
      await client.from('leaves').insert(<String, Object?>{
        'organization_id': me.organizationId,
        'student_id': me.studentId,
        'membership_id': me.membershipId,
        'start_date': _dateOnly(start),
        'end_date': _dateOnly(end),
        'reason': reason.trim(),
      });
      AuditService.record('student.leave_applied');
    } catch (error, stackTrace) {
      AppLog.error('student.leave_failed', error, stackTrace);
      throw StudentException('Could not send your request. Please try again.');
    }
  }

  /// Payment history, newest first. Fee names come from the embedded
  /// fee_structures row, which is null for ad-hoc charges.
  static Future<List<PaymentRecord>> payments(StudentIdentity me) async {
    final client = _require;
    final rows = await client
        .from('payments')
        .select('id, amount, status, payment_method, paid_at, due_date, '
            'fee_structures(name)')
        .eq('organization_id', me.organizationId)
        .eq('membership_id', me.membershipId)
        .order('created_at', ascending: false)
        .limit(50);

    return rows.map((row) {
      final fee = row['fee_structures'] as Map<String, dynamic>?;
      final amount = row['amount'];
      return PaymentRecord(
        amount: amount is num ? amount : 0,
        status: row['status'] as String? ?? 'pending',
        method: row['payment_method'] as String? ?? 'cash',
        paidAt: _parseDate(row['paid_at']),
        dueDate: _parseDate(row['due_date']),
        feeName: fee?['name'] as String? ?? 'Fees',
      );
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> feeStructures(
      StudentIdentity me) async {
    final client = _require;
    return client
        .from('fee_structures')
        .select('id, name, amount, frequency, description')
        .eq('organization_id', me.organizationId)
        .eq('is_active', true)
        .order('name');
  }

  /// This student's attendance, most recent first.
  static Future<List<Map<String, dynamic>>> attendance(
      StudentIdentity me) async {
    final client = _require;
    return client
        .from('attendance_records')
        .select('id, session_id, class_id, status, note, created_at')
        .eq('organization_id', me.organizationId)
        .eq('student_id', me.studentId)
        .order('created_at', ascending: false)
        .limit(30);
  }

  /// Class names, so an attendance row or enrollment can be labelled.
  static Future<Map<String, String>> classNames(StudentIdentity me) async {
    final client = _require;
    final rows = await client
        .from('classes')
        .select('id, name')
        .eq('organization_id', me.organizationId);
    return <String, String>{
      for (final row in rows)
        if (row['id'] is String)
          row['id'] as String: row['name'] as String? ?? '',
    };
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
