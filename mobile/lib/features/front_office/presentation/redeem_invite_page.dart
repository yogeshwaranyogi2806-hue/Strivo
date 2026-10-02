import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/services/invitation_service.dart';
import '../../../core/services/log_service.dart';

/// Redeems an invitation for somebody who is *already* signed in.
///
/// This is a different job from /signup, which creates a new auth account. A
/// person who signed up before their admin sent the invite arrives here with a
/// login but no membership, and sending them to /signup would try to create a
/// second account for the same address. All this page does is check the code and
/// attach the account to the studio.
class RedeemInvitePage extends StatefulWidget {
  const RedeemInvitePage({super.key});

  @override
  State<RedeemInvitePage> createState() => _RedeemInvitePageState();
}

class _RedeemInvitePageState extends State<RedeemInvitePage> {
  final _codeController = TextEditingController();
  InvitationPreview? _preview;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await InvitationService.lookup(_codeController.text);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on InvitationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await InvitationService.accept(_codeController.text);
      if (!mounted) return;
      // The router re-resolves the role on the next redirect, so this lands in
      // whichever app the new membership belongs to.
      AppLog.info('invitation.redeemed_by_existing_account');
      context.go('/resolving');
    } on InvitationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Enter invitation code')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Join your studio',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Your account is set up but not yet linked to a studio. Enter the '
            'code your coach sent you.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: StrivoColors.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _codeController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Invitation code',
              hintText: 'A1B2 C3D4 E5F6 0718',
            ),
          ),
          const SizedBox(height: 14),
          if (preview != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Color(0xFF2E9E68), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Joining ${preview.organizationName}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'as ${preview.role.label}',
                            style: const TextStyle(
                                fontSize: 12, color: StrivoColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _accept,
              child: const Text('Join studio'),
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : _check,
              child: Text(preview == null ? 'Check code' : 'Check again'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 26),
          const Divider(),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    Clipboard.setData(
                        ClipboardData(text: _codeController.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied.')),
                    );
                  },
            icon: const Icon(Icons.copy, size: 17),
            label: const Text('Paste code instead'),
          ),
        ],
      ),
    );
  }
}
