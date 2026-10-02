import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/services/content_service.dart';

/// The fix-it list for students who signed up but have no student record
/// attached. Normally accept_invitation links them automatically by name. Two
/// cases need a human: a name that did not match, and a studio with two
/// unlinked students sharing a name where the automatic match was refused.
///
/// This page only shows the mismatch. It never invents a match: the coach has
/// to choose which login belongs to which record.
class StudentLinksPage extends StatefulWidget {
  const StudentLinksPage({super.key});

  @override
  State<StudentLinksPage> createState() => _StudentLinksPageState();
}

class _StudentLinksPageState extends State<StudentLinksPage> {
  late Future<List<UnlinkedStudent>> _future;

  @override
  void initState() {
    super.initState();
    _future = ContentService.unlinkedStudents();
  }

  void _reload() => setState(() => _future = ContentService.unlinkedStudents());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student records')),
      body: FutureBuilder<List<UnlinkedStudent>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  error is ContentException
                      ? error.message
                      : 'Could not load the student list.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final all = snapshot.data ?? const <UnlinkedStudent>[];
          final records = all.where((u) => u.isRecord).toList();
          final logins = all.where((u) => u.isLogin).toList();

          if (all.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 34, color: Color(0xFF2E9E68)),
                    SizedBox(height: 12),
                    Text(
                      'Every student record is linked to a login.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF0DFB8)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 20, color: Color(0xFF9A6B12)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'These students can sign in but cannot see their '
                        'attendance, tasks or fees until they are matched up.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (logins.isNotEmpty) ...[
                Text('Logins waiting to be matched',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final login in logins)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      radius: 18,
                      child: Icon(Icons.person_outline, size: 18),
                    ),
                    title: Text(login.label),
                    subtitle: const Text('Signed up, no student record',
                        style: TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 20),
              ],
              if (records.isNotEmpty) ...[
                Text('Records with no login',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Added by a coach before the student ever signed up.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: StrivoColors.muted),
                ),
                const SizedBox(height: 10),
                for (final record in records)
                  _UnlinkedRecord(
                    record: record,
                    logins: logins,
                    onLinked: _reload,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UnlinkedRecord extends StatelessWidget {
  const _UnlinkedRecord({
    required this.record,
    required this.logins,
    required this.onLinked,
  });

  final UnlinkedStudent record;
  final List<UnlinkedStudent> logins;
  final VoidCallback onLinked;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (logins.isEmpty)
              const Text(
                'No waiting login. Invite this student, or add them again '
                'through a new invitation.',
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: StrivoColors.muted),
              )
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Link to login',
                  isDense: true,
                ),
                items: [
                  for (final login in logins)
                    DropdownMenuItem<String>(
                      value: login.membershipId,
                      child: Text(login.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (membershipId) async {
                  if (membershipId == null) return;
                  try {
                    await ContentService.linkStudent(
                      studentId: record.studentId!,
                      membershipId: membershipId,
                    );
                    onLinked();
                  } on ContentException catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error.message)));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
