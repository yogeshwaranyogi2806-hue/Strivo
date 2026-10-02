import 'package:flutter_test/flutter_test.dart';
import 'package:strivo/core/services/student_service.dart';

LeaveRequest leave({
  String start = '2026-03-02',
  String end = '2026-03-04',
  String status = 'pending',
  String reason = '',
  String reviewNote = '',
}) =>
    LeaveRequest(
      id: 'leave-1',
      startDate: DateTime.parse(start),
      endDate: DateTime.parse(end),
      reason: reason,
      status: LeaveStatus.fromValue(status),
      reviewNote: reviewNote,
    );

TaskWithSubmission task({
  String? dueDate,
  Map<String, dynamic>? submission,
}) =>
    TaskWithSubmission(
      task: <String, dynamic>{
        'id': 'task-1',
        'title': 'Shadow technique',
        'due_date': dueDate,
      },
      submission: submission,
    );

void main() {
  group('LeaveStatus', () {
    test('labels read as a status rather than a database value', () {
      expect(LeaveStatus.fromValue('pending').label, 'Awaiting review');
      expect(LeaveStatus.fromValue('approved').label, 'Approved');
      expect(LeaveStatus.fromValue('rejected').label, 'Not approved');
    });

    test('an unknown status is treated as pending, not approved', () {
      expect(LeaveStatus.fromValue('cancelled'), LeaveStatus.pending);
      expect(LeaveStatus.fromValue(null), LeaveStatus.pending);
    });
  });

  group('LeaveRequest.dayCount', () {
    test('a single day counts as one, not zero', () {
      expect(leave(start: '2026-03-02', end: '2026-03-02').dayCount, 1);
    });

    test('counts both ends inclusively', () {
      expect(leave(start: '2026-03-02', end: '2026-03-04').dayCount, 3);
    });

    test('spans a weekend without skipping it', () {
      // Fri 6th to Sun 8th is three days of leave, not one working day.
      expect(leave(start: '2026-03-06', end: '2026-03-08').dayCount, 3);
    });

    test('crosses a month boundary', () {
      expect(leave(start: '2026-03-30', end: '2026-04-02').dayCount, 4);
    });
  });

  group('TaskWithSubmission', () {
    test('a task with no due date is never overdue', () {
      expect(task(dueDate: null).isOverdue, isFalse);
      expect(task(dueDate: null).daysUntilDue, isNull);
    });

    test('a submitted task is never overdue even if the date has passed', () {
      final submitted = task(
        dueDate: '2020-01-01',
        submission: <String, dynamic>{'id': 'sub-1'},
      );
      expect(submitted.isSubmitted, isTrue);
      expect(submitted.isOverdue, isFalse);
    });

    test('an unparseable due date does not crash the badge', () {
      final broken = task(dueDate: 'not-a-date');
      expect(broken.isOverdue, isFalse);
      expect(broken.daysUntilDue, isNull);
    });

    test('a future due date counts down', () {
      final soon = task(
        dueDate: DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String()
            .substring(0, 10),
      );
      expect(soon.daysUntilDue, 3);
      expect(soon.isOverdue, isFalse);
    });
  });

  group('PaymentRecord', () {
    PaymentRecord payment(String status) => PaymentRecord(
          amount: 1500,
          status: status,
          method: 'cash',
          paidAt: null,
          dueDate: null,
          feeName: 'Monthly fee',
        );

    test('pending and failed count as outstanding', () {
      expect(payment('pending').isOutstanding, isTrue);
      expect(payment('failed').isOutstanding, isTrue);
    });

    test('completed and refunded do not', () {
      expect(payment('completed').isOutstanding, isFalse);
      expect(payment('refunded').isOutstanding, isFalse);
    });
  });
}