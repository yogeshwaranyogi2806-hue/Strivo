import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/log_service.dart';
import '../../../core/services/membership_service.dart';

/// A signed-in account that belongs to no studio. This is a real state: an
/// invitation can be created for somebody who has not signed up yet, and it is
/// also where the very first admin lands on a fresh deployment.
///
/// Studio creation is offered *only* while the whole deployment has no coach at
/// all. Once one exists the button disappears for good, which closes the
/// self-registration hole that invitations exist to prevent while still letting
/// the first person get started without anyone running SQL by hand.
class NoWorkspacePage extends StatefulWidget {
  const NoWorkspacePage({super.key});

  @override
  State<NoWorkspacePage> createState() => _NoWorkspacePageState();
}

class _NoWorkspacePageState extends State<NoWorkspacePage> {
  bool _canBootstrap = false;
  bool _checkedBootstrap = false;
  String? _signedInAs;

  @override
  void initState() {
    super.initState();
    // Without this the screen gives no clue which account is signed in, so
    // somebody who logged in with the wrong one cannot tell what went wrong.
    _signedInAs = Supabase.instance.client.auth.currentUser?.email;
    _checkBootstrap();
  }

  Future<void> _checkBootstrap() async {
    final needed = await MembershipService.deploymentNeedsBootstrap();
    if (!mounted) return;
    setState(() {
      _canBootstrap = needed;
      _checkedBootstrap = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strivo'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hourglass_empty,
                    size: 34, color: StrivoColors.navy),
                const SizedBox(height: 18),
                Text('You are signed in, but not part of a studio yet',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  'Access is granted by the coach who runs your studio. Ask them '
                  'for an invitation code, then use it below to finish setting '
                  'up your account.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: StrivoColors.muted, height: 1.5),
                ),
                const SizedBox(height: 26),
                if (_signedInAs != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StrivoColors.muted.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Signed in as',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: StrivoColors.muted)),
                        const SizedBox(height: 2),
                        SelectableText(
                          _signedInAs!,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                FilledButton.icon(
                  onPressed: () {
                    AppLog.info('no_workspace.looking_for_invite');
                    // /redeem, not /signup: the person is already signed in, so
                    // they only need to attach this account to a studio.
                    context.go('/redeem');
                  },
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: const Text('I have an invitation code'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    AppLog.info('no_workspace.signing_out');
                    // Must actually end the session. Navigating to /login while
                    // still signed in makes the router bounce straight back here.
                    await AuthService.signOutAndReturnToLogin(
                      () => context.go('/login'),
                    );
                  },
                  child: const Text('Sign in with a different account'),
                ),
                const SizedBox(height: 24),
                Text(
                  'If you were expecting access, your coach needs to send a new '
                  'invite -- an invite can only be redeemed once.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: StrivoColors.muted, height: 1.5),
                ),
                if (_canBootstrap) ...[
                  const SizedBox(height: 26),
                  const Divider(),
                  const SizedBox(height: 18),
                  Text('Setting up for the first time?',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'No studio exists on this deployment yet, so you can create '
                    'the first one. This option disappears once a coach is set up.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: StrivoColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  _CreateWorkspaceCard(
                    onCreated: () => context.go('/resolving'),
                  ),
                ] else if (!_checkedBootstrap) ...[
                  const SizedBox(height: 26),
                  const Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collects a studio name and calls the RPC. Split out so the form keeps its own
/// busy/error state instead of re-rendering the whole screen on every keystroke.
class _CreateWorkspaceCard extends StatefulWidget {
  const _CreateWorkspaceCard({required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<_CreateWorkspaceCard> createState() => _CreateWorkspaceCardState();
}

class _CreateWorkspaceCardState extends State<_CreateWorkspaceCard> {
  final _nameController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Give the studio a name (at least 2 letters).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MembershipService.createFirstWorkspace(name);
      AppLog.info('no_workspace.workspace_created');
      if (!mounted) return;
      _nameController.clear();
      widget.onCreated();
    } on MembershipException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Studio name',
            hintText: 'Strivo Football Academy',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(_busy ? 'Creating...' : 'Create studio'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
