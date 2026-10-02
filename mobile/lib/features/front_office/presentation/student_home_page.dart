import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/student_service.dart';

/// Loads the signed-in student's identity and holds the cached data that the
/// tabs read from. Identity is the gate: nothing else loads until it resolves.
class _StudentData {
  const _StudentData({
    required this.me,
    required this.announcements,
    required this.tasks,
    required this.leaves,
    required this.payments,
    required this.fees,
    required this.attendance,
    required this.classNames,
  });

  final StudentIdentity me;
  final List<Map<String, dynamic>> announcements;
  final List<TaskWithSubmission> tasks;
  final List<LeaveRequest> leaves;
  final List<PaymentRecord> payments;
  final List<Map<String, dynamic>> fees;
  final List<Map<String, dynamic>> attendance;
  final Map<String, String> classNames;

  List<TaskWithSubmission> get openTasks =>
      tasks.where((t) => !t.isSubmitted).toList();

  List<TaskWithSubmission> get doneTasks =>
      tasks.where((t) => t.isSubmitted).toList();

  List<PaymentRecord> get outstanding =>
      payments.where((p) => p.isOutstanding).toList();

  num get outstandingTotal =>
      outstanding.fold<num>(0, (sum, p) => sum + p.amount);

  double? get attendanceRate {
    if (attendance.isEmpty) return null;
    final present = attendance
        .where((r) => r['status'] == 'present' || r['status'] == 'late')
        .length;
    return present / attendance.length;
  }
}

final studentDataProvider =
    FutureProvider.autoDispose<_StudentData>((ref) async {
  final me = await StudentService.identity();
  // Load the panels together, but keep one failure from hiding the rest.
  final results = await Future.wait([
    StudentService.announcements(me),
    StudentService.tasks(me),
    StudentService.leaves(me),
    StudentService.payments(me),
    StudentService.feeStructures(me),
    StudentService.attendance(me),
    StudentService.classNames(me),
  ]);
  return _StudentData(
    me: me,
    announcements: results[0] as List<Map<String, dynamic>>,
    tasks: results[1] as List<TaskWithSubmission>,
    leaves: results[2] as List<LeaveRequest>,
    payments: results[3] as List<PaymentRecord>,
    fees: results[4] as List<Map<String, dynamic>>,
    attendance: results[5] as List<Map<String, dynamic>>,
    classNames: results[6] as Map<String, String>,
  );
});

/// The student-facing shell. Deliberately a separate tree from the coach
/// back office: students never see coach tools, and never see the invite page.
class StudentHomePage extends ConsumerStatefulWidget {
  const StudentHomePage({super.key});

  @override
  ConsumerState<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends ConsumerState<StudentHomePage> {
  int _tab = 0;

  static const _titles = ['Home', 'Tasks', 'Leave', 'Fees', 'You'];

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(studentDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Activity log',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/logs'),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _StudentError(error: error),
        data: (student) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(studentDataProvider),
          child: IndexedStack(
            index: _tab,
            children: [
              _HomeTab(data: student),
              _TasksTab(data: student),
              _LeaveTab(data: student),
              _FeesTab(data: student),
              _LibraryTab(data: student),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined), label: 'Tasks'),
          NavigationDestination(
              icon: Icon(Icons.event_busy_outlined), label: 'Leave'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined), label: 'Fees'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), label: 'You'),
        ],
      ),
    );
  }
}

class _StudentError extends StatelessWidget {
  const _StudentError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final failure = error;
    final message = failure is StudentException
        ? failure.message
        : 'Something went wrong loading your account.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 34, color: StrivoColors.muted),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.data});

  final _StudentData data;

  @override
  Widget build(BuildContext context) {
    final rate = data.attendanceRate;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          'Hello, ${data.me.fullName.split(' ').first}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Here is where you stand today.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: StrivoColors.muted),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${data.openTasks.length}',
                label: data.openTasks.length == 1 ? 'Task due' : 'Tasks due',
                icon: Icons.assignment_outlined,
                warn: data.openTasks.any((t) => t.isOverdue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: rate == null ? '--' : '${(rate * 100).round()}%',
                label: 'Attendance',
                icon: Icons.how_to_reg_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value:
                    '${data.leaves.where((l) => l.status == LeaveStatus.pending).length}',
                label: 'Leave pending',
                icon: Icons.event_busy_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: data.outstanding.isEmpty
                    ? 'Paid'
                    : _money(data.outstandingTotal),
                label: data.outstanding.isEmpty ? 'All settled' : 'Outstanding',
                icon: Icons.payments_outlined,
                warn: data.outstanding.isNotEmpty,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text('Announcements', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (data.announcements.isEmpty)
          const _EmptyNote('Nothing posted from your studio yet.')
        else
          for (final post in data.announcements) _AnnouncementCard(post: post),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final priority = post['priority'] as String? ?? 'normal';
    final urgent = priority == 'urgent' || priority == 'high';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          urgent ? Icons.priority_high : Icons.campaign_outlined,
          color: urgent ? const Color(0xFFD64545) : StrivoColors.navy,
        ),
        title: Text(post['title'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: (post['body'] as String?)?.isNotEmpty == true
            ? Text((post['body'] as String).trim())
            : null,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    this.warn = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFDECEC) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: warn ? const Color(0xFFF2C9C9) : const Color(0xFFE0E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 20,
              color: warn ? const Color(0xFFD64545) : StrivoColors.muted),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: warn ? const Color(0xFFD64545) : StrivoColors.deepNavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 12, color: StrivoColors.muted)),
        ],
      ),
    );
  }
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab({required this.data});

  final _StudentData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.tasks.isEmpty) {
      return const _EmptyState(
        icon: Icons.assignment_outlined,
        title: 'No tasks yet',
        message:
            'When your coach sets work for your class it will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (data.openTasks.isNotEmpty) ...[
          Text('To do (${data.openTasks.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final task in data.openTasks)
            _TaskCard(
              task: task,
              className: data.classNames[task.classId] ?? '',
              onSubmit: () => _openSubmitSheet(context, ref, task),
            ),
          const SizedBox(height: 24),
        ],
        if (data.doneTasks.isNotEmpty) ...[
          Text('Submitted (${data.doneTasks.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final task in data.doneTasks)
            _TaskCard(
              task: task,
              className: data.classNames[task.classId] ?? '',
            ),
        ],
      ],
    );
  }

  void _openSubmitSheet(
      BuildContext context, WidgetRef ref, TaskWithSubmission task) {
    final controller = TextEditingController(
        text: task.submission?['submission_text'] as String? ?? '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 18,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            if ((task.task['description'] as String?)?.isNotEmpty == true)
              Text(
                task.task['description'] as String,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: StrivoColors.muted, height: 1.4),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Your work',
                hintText: 'Type your answer or a link to it',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  await StudentService.submitTask(
                    me: data.me,
                    taskId: task.task['id'] as String,
                    answer: controller.text,
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  ref.invalidate(studentDataProvider);
                } on StudentException catch (error) {
                  if (!sheetContext.mounted) return;
                  ScaffoldMessenger.of(sheetContext)
                      .showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              child: Text(task.isSubmitted ? 'Update work' : 'Submit work'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => controller.dispose());
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.className, this.onSubmit});

  final TaskWithSubmission task;
  final String className;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final days = task.daysUntilDue;
    final overdue = task.isOverdue;
    final submitted = task.isSubmitted;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (submitted)
                  const Icon(Icons.check_circle,
                      color: Color(0xFF2E9E68), size: 19)
                else if (overdue)
                  const Icon(Icons.error_outline,
                      color: Color(0xFFD64545), size: 19),
              ],
            ),
            if (className.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(className,
                  style:
                      const TextStyle(fontSize: 12, color: StrivoColors.muted)),
            ],
            if ((task.task['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 7),
              Text(
                task.task['description'] as String,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
            if (submitted) ...[
              const SizedBox(height: 9),
              _SubmittedBody(submission: task.submission!),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (task.dueDate != null)
                  Text(
                    _dueLabel(days, overdue, submitted),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: overdue
                          ? const Color(0xFFD64545)
                          : StrivoColors.muted,
                    ),
                  ),
                const Spacer(),
                if (onSubmit != null)
                  TextButton(onPressed: onSubmit, child: const Text('Submit')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dueLabel(int? days, bool overdue, bool submitted) {
    final base = task.dueDate ?? '';
    if (submitted) return 'Submitted';
    if (overdue) return 'Was due $base';
    if (days == 0) return 'Due today';
    if (days != null && days > 0) {
      return days == 1 ? 'Due tomorrow' : 'Due in $days days';
    }
    return 'Due $base';
  }
}

class _SubmittedBody extends StatelessWidget {
  const _SubmittedBody({required this.submission});

  final Map<String, dynamic> submission;

  @override
  Widget build(BuildContext context) {
    final rating = submission['rating'] as int?;
    final reviewNote = submission['review_note'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(submission['submission_text'] as String? ?? '',
              style: const TextStyle(fontSize: 13, height: 1.4)),
          if (rating != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Marked',
                    style: TextStyle(fontSize: 12, color: StrivoColors.muted)),
                const SizedBox(width: 6),
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: const Color(0xFFF0A93B),
                  ),
              ],
            ),
          ],
          if (reviewNote.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('Coach: $reviewNote',
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _LeaveTab extends ConsumerWidget {
  const _LeaveTab({required this.data});

  final _StudentData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openApplySheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Apply'),
      ),
      body: data.leaves.isEmpty
          ? const _EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No leave requests',
              message:
                  'Apply for leave when you need it. Your coach will see it straight away.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: data.leaves.length,
              itemBuilder: (context, index) =>
                  _LeaveCard(leave: data.leaves[index]),
            ),
    );
  }

  void _openApplySheet(BuildContext context, WidgetRef ref) {
    var start = DateTime.now().add(const Duration(days: 1));
    var end = start;
    final reason = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 18,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apply for leave',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'First day',
                      value: start,
                      onPick: (picked) => setSheetState(() {
                        start = picked;
                        if (end.isBefore(picked)) end = picked;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateButton(
                      label: 'Last day',
                      value: end,
                      onPick: (picked) => setSheetState(() => end = picked),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  try {
                    await StudentService.applyForLeave(
                      me: data.me,
                      start: start,
                      end: end,
                      reason: reason.text,
                    );
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    AuditService.record('student.leave_applied');
                    ref.invalidate(studentDataProvider);
                  } on StudentException catch (error) {
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(sheetContext)
                        .showSnackBar(SnackBar(content: Text(error.message)));
                  }
                },
                child: const Text('Send request'),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => reason.dispose());
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 730)),
        );
        if (picked != null) onPick(picked);
      },
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(_shortDate(value), style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.leave});

  final LeaveRequest leave;

  @override
  Widget build(BuildContext context) {
    final colour = switch (leave.status) {
      LeaveStatus.approved => const Color(0xFF2E9E68),
      LeaveStatus.rejected => const Color(0xFFD64545),
      LeaveStatus.pending => const Color(0xFFF0A93B),
    };
    final days = leave.dayCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_shortDate(leave.startDate)}'
                    '${leave.startDate == leave.endDate ? '' : ' - ${_shortDate(leave.endDate)}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    leave.status.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colour),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              days == 1 ? '1 day' : '$days days',
              style: const TextStyle(fontSize: 12, color: StrivoColors.muted),
            ),
            if (leave.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(leave.reason,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
            if (leave.reviewNote.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text('Coach: ${leave.reviewNote}',
                  style: const TextStyle(fontSize: 12, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeesTab extends StatelessWidget {
  const _FeesTab({required this.data});

  final _StudentData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (data.outstanding.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF2C9C9)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFD64545)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_money(data.outstandingTotal)} outstanding across '
                    '${data.outstanding.length} '
                    '${data.outstanding.length == 1 ? 'item' : 'items'}.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (data.payments.isEmpty)
          const _EmptyNote('No payments recorded yet.')
        else
          for (final payment in data.payments) _PaymentRow(payment: payment),
        if (data.fees.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('What your studio charges',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final fee in data.fees)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(fee['name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${(fee['amount'] as num?)?.toStringAsFixed(0) ?? ''} '
                '${_frequency(fee['frequency'] as String?)}',
              ),
            ),
        ],
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final PaymentRecord payment;

  @override
  Widget build(BuildContext context) {
    final settled = !payment.isOutstanding;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        settled ? Icons.check_circle_outline : Icons.schedule,
        color: settled ? const Color(0xFF2E9E68) : const Color(0xFFF0A93B),
      ),
      title: Text(payment.feeName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        <String>[
          if (payment.dueDate != null) 'Due ${_shortDate(payment.dueDate!)}',
          if (payment.paidAt != null) 'Paid ${_shortDate(payment.paidAt!)}',
          _method(payment.method),
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        _money(payment.amount),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({required this.data});

  final _StudentData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: const Icon(Icons.video_library_outlined,
                color: StrivoColors.navy),
            title: const Text('Library',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle:
                const Text('Videos, articles and documents from your coach.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/library'),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(data.me.fullName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Student'),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            // End the session first, or the router bounces straight back to
            // the dashboard being left.
            await AuthService.signOutAndReturnToLogin(
                () => context.go('/login'));
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
        const Divider(height: 28),
        Text('Attendance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (data.attendance.isEmpty)
          const _EmptyNote('No attendance recorded yet.')
        else
          for (final record in data.attendance.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                switch (record['status'] as String?) {
                  'present' => Icons.check_circle_outline,
                  'absent' => Icons.cancel_outlined,
                  'late' => Icons.schedule,
                  _ => Icons.circle_outlined,
                },
                color: switch (record['status'] as String?) {
                  'present' => const Color(0xFF2E9E68),
                  'absent' => const Color(0xFFD64545),
                  _ => StrivoColors.muted,
                },
              ),
              title: Text(
                data.classNames[record['class_id']] ?? 'Class',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                (record['status'] as String? ?? '').toUpperCase(),
                style: const TextStyle(fontSize: 11, color: StrivoColors.muted),
              ),
            ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: StrivoColors.muted),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: StrivoColors.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: StrivoColors.muted),
      ),
    );
  }
}

String _shortDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _money(num amount) => '₹${amount.toStringAsFixed(0)}';

String _frequency(String? value) => switch (value) {
      'monthly' => 'per month',
      'quarterly' => 'per quarter',
      'yearly' => 'per year',
      'one_time' => 'one time',
      _ => '',
    };

String _method(String value) => switch (value) {
      'cash' => 'Cash',
      'card' => 'Card',
      'upi' => 'UPI',
      'bank_transfer' => 'Bank transfer',
      'online' => 'Online',
      _ => value,
    };
