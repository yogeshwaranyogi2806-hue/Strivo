import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/services/invitation_service.dart';
import '../../../core/services/log_service.dart';

/// Where an existing admin generates an invite to hand to a new coach or a
/// student. This is the only way a new account comes into existence.
class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  static const List<(int, String)> _expiryOptions = [
    (7, '7 days'),
    (14, '14 days'),
    (30, '30 days'),
  ];

  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  InviteRole _role = InviteRole.student;
  int _expiresDays = 14;
  String? _issued;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
      _issued = null;
    });
    try {
      final token = await InvitationService.create(
        role: _role,
        email: _emailController.text,
        fullName: _nameController.text,
        expiresDays: _expiresDays,
      );
      if (!mounted) return;
      setState(() => _issued = token);
    } on InvitationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite someone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Send a code', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'They enter this code when creating their account. An invite works once '
            'and expires on the date you choose.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: StrivoColors.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          Text('Joining as', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<InviteRole>(
            segments: const [
              ButtonSegment(value: InviteRole.owner, label: Text('Admin')),
              ButtonSegment(value: InviteRole.coach, label: Text('Coach')),
              ButtonSegment(value: InviteRole.student, label: Text('Student')),
            ],
            selected: <InviteRole>{_role},
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() => _role = selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_role) {
              InviteRole.owner =>
                'Full access, including sending more invites.',
              InviteRole.coach =>
                'Can manage classes, students and assessments.',
              InviteRole.student =>
                'Can apply for leave, submit tasks and see fees.',
            },
            style: const TextStyle(
                fontSize: 12, color: StrivoColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Their name (optional)',
              helperText: 'Only used to help you recognise the invite.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Their email (optional)',
              helperText:
                  'Locks the invite to that address. Leave blank for an open code.',
            ),
          ),
          const SizedBox(height: 16),
          Text('Valid for', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (days, label) in _expiryOptions)
                ChoiceChip(
                  label: Text(label),
                  selected: _expiresDays == days,
                  onSelected:
                      _busy ? null : (_) => setState(() => _expiresDays = days),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(
                _issued == null ? 'Generate invitation' : 'Generate another'),
          ),
          if (_issued != null) ...[
            const SizedBox(height: 22),
            _IssuedCard(
              token: _issued!,
              role: _role,
              expiresDays: _expiresDays,
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _IssuedCard extends StatelessWidget {
  const _IssuedCard({
    required this.token,
    required this.role,
    required this.expiresDays,
  });

  final String token;
  final InviteRole role;
  final int expiresDays;

  @override
  Widget build(BuildContext context) {
    final code = InvitationService.formatCode(token);
    final message =
        'Hi! Here is your Strivo invitation for ${role.label.toLowerCase()} access. '
        '\n\nCode: $code\n\nIt works once and expires in $expiresDays days. '
        'Open the app, tap "Create account", and enter the code.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Color(0xFF2E9E68), size: 20),
                const SizedBox(width: 8),
                Text('Invitation ready',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE0E5EC)),
              ),
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      AppLog.info('invitation.code_copied');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy code'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message));
                      AppLog.info('invitation.message_copied');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Message copied. Paste it into WhatsApp.')),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Copy message'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Share it however you normally reach them. A deep link that opens the app '
              'straight on this code is not wired up yet, so send the code itself.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: StrivoColors.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
