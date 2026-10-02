import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/providers.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/invitation_service.dart';
import '../../../core/services/log_service.dart';

/// Two-step registration: prove you were invited, then create your own login.
///
/// Step one is a code check rather than a plain form because this project has no
/// open sign-up. Step two creates the Supabase account and redeems the
/// invitation, which is what actually grants the membership.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

enum _Stage { code, details, confirmEmail }

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Stage _stage = _Stage.code;
  InvitationPreview? _invitation;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await InvitationService.lookup(_codeController.text);
      if (!mounted) return;
      setState(() {
        _invitation = preview;
        _stage = _Stage.details;
        // An invite tied to one mailbox pre-fills it and locks the field.
        if (preview.invitedEmail != null && preview.invitedEmail!.isNotEmpty) {
          _emailController.text = preview.invitedEmail!;
        }
      });
    } on InvitationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_invitation == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final token = InvitationService.normaliseCode(_codeController.text);
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      setState(() => _error = 'Connect your Strivo workspace to continue.');
      return;
    }

    try {
      final response = await client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: <String, Object?>{'full_name': _nameController.text.trim()},
      );

      if (response.session == null) {
        // Email confirmation is switched on for this project. Remember the code
        // so it can be redeemed the moment they sign in.
        InvitationService.rememberPending(token);
        AuditService.record('auth.signup_confirm_email_required');
        if (mounted) setState(() => _stage = _Stage.confirmEmail);
        return;
      }

      await InvitationService.accept(token);
      InvitationService.clearPending();
      AuditService.record(
        'auth.signup_completed',
        detail: 'role=${_invitation!.role.value}',
      );
      if (mounted) context.go('/home');
    } on AuthException catch (error) {
      AppLog.warn('auth.signup_failed', detail: 'status=${error.statusCode}');
      if (mounted) {
        setState(() => _error = _friendly(error.statusCode));
      }
    } on InvitationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error, stackTrace) {
      AppLog.error('auth.signup_failed_unexpected', error, stackTrace);
      if (mounted) {
        setState(
            () => _error = 'Could not create the account. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String? statusCode) {
    final status = int.tryParse(statusCode ?? '');
    if (status == 422 || status == 400) {
      return 'That email address is already registered, or the password is too short.';
    }
    if (status == 429) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'Could not create the account. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: switch (_stage) {
                    _Stage.code => _buildCodeStep(),
                    _Stage.details => _buildDetailsStep(),
                    _Stage.confirmEmail => _buildConfirmStep(),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Brand(),
        const SizedBox(height: 28),
        Text('Join with an invitation',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Strivo accounts are created by invitation. Enter the code your studio sent you.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: StrivoColors.muted),
        ),
        const SizedBox(height: 22),
        TextFormField(
          controller: _codeController,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9 ]')),
            LengthLimitingTextInputFormatter(24),
          ],
          decoration: const InputDecoration(
            labelText: 'Invitation code',
            hintText: 'XXXX XXXX XXXX XXXX',
          ),
          onFieldSubmitted: (_) => _checkCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _checkCode,
          child: _busy ? const _Spinner() : const Text('Check invitation'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : () => context.go('/login'),
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }

  Widget _buildDetailsStep() {
    final invitation = _invitation!;
    final emailLocked = !invitation.openToAnyone;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          const SizedBox(height: 22),
          _InvitationBanner(invitation: invitation),
          const SizedBox(height: 22),
          Text('Create your login',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (value) => (value == null || value.trim().length < 2)
                ? 'Enter your full name.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            // Locked when the invitation was issued to one specific mailbox.
            readOnly: emailLocked,
            enabled: !_busy && !emailLocked,
            decoration: InputDecoration(
              labelText: 'Email address',
              helperText: emailLocked
                  ? 'This invitation is tied to this address.'
                  : null,
            ),
            validator: (value) => (value == null || !value.contains('@'))
                ? 'Enter a valid email address.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (value) => (value == null || value.length < 8)
                ? 'Use at least 8 characters.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Confirm password'),
            validator: (value) => value != _passwordController.text
                ? 'Passwords do not match.'
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _createAccount,
            child: _busy ? const _Spinner() : const Text('Create account'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed:
                _busy ? null : () => setState(() => _stage = _Stage.code),
            child: const Text('Use a different code'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Brand(),
        const SizedBox(height: 28),
        const Icon(Icons.mark_email_read_outlined,
            color: StrivoColors.coral, size: 40),
        const SizedBox(height: 18),
        Text('Check your inbox',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'We sent a confirmation link to ${_emailController.text.trim()}. '
          'Open it, then sign in and your invitation will be applied automatically.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: StrivoColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Go to sign in'),
        ),
      ],
    );
  }
}

class _InvitationBanner extends StatelessWidget {
  const _InvitationBanner({required this.invitation});

  final InvitationPreview invitation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD6E2FA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_outlined,
              color: StrivoColors.navy, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.organizationName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Joining as ${invitation.role.label}',
                  style:
                      const TextStyle(fontSize: 12, color: StrivoColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.all_inclusive_rounded,
            size: 30, color: StrivoColors.coral),
        const SizedBox(width: 8),
        Text('Strivo',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: StrivoColors.deepNavy,
                  fontWeight: FontWeight.w800,
                )),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
