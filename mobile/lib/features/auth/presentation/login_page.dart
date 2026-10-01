import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/providers.dart';

enum _LoginMethod { email, mobile }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  _LoginMethod _method = _LoginMethod.email;
  bool _waitingForOtp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = ref.read(supabaseClientProvider)!;
      if (_method == _LoginMethod.email) {
        await client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else if (!_waitingForOtp) {
        await client.auth.signInWithOtp(
          phone: _phoneController.text.trim(),
          shouldCreateUser: false,
        );
        setState(() => _waitingForOtp = true);
      } else {
        await client.auth.verifyOTP(
          phone: _phoneController.text.trim(),
          token: _otpController.text.trim(),
          type: OtpType.sms,
        );
      }
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Sign-in failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeMethod(Set<_LoginMethod> selection) {
    setState(() {
      _method = selection.first;
      _waitingForOtp = false;
      _error = null;
    });
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _LoginBrand(),
                        const SizedBox(height: 28),
                        Text('Welcome back',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to manage your coaching workspace.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: StrivoColors.muted,
                              ),
                        ),
                        const SizedBox(height: 22),
                        SegmentedButton<_LoginMethod>(
                          segments: const [
                            ButtonSegment(
                              value: _LoginMethod.email,
                              label: Text('Email'),
                              icon: Icon(Icons.email_outlined),
                            ),
                            ButtonSegment(
                              value: _LoginMethod.mobile,
                              label: Text('Mobile'),
                              icon: Icon(Icons.phone_android),
                            ),
                          ],
                          selected: {_method},
                          onSelectionChanged: _changeMethod,
                        ),
                        const SizedBox(height: 18),
                        if (_method == _LoginMethod.email) ...[
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(labelText: 'Email address'),
                            validator: (value) => value == null || !value.contains('@')
                                ? 'Enter a valid email address.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: const InputDecoration(labelText: 'Password'),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Enter your password.'
                                : null,
                          ),
                        ] else ...[
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            decoration: const InputDecoration(
                              labelText: 'Mobile number',
                              hintText: '+91 98765 43210',
                            ),
                            validator: (value) => value == null || value.trim().length < 8
                                ? 'Enter your mobile number with country code.'
                                : null,
                          ),
                          if (_waitingForOtp) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              decoration: const InputDecoration(
                                  labelText: 'Verification code'),
                              validator: (value) => value == null || value.trim().length < 4
                                  ? 'Enter the code sent to your phone.'
                                  : null,
                            ),
                          ],
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_method == _LoginMethod.mobile && !_waitingForOtp
                                  ? 'Send verification code'
                                  : 'Sign in'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _method == _LoginMethod.mobile
                              ? 'Phone sign-in requires SMS verification configured in Supabase.'
                              : 'Use the coach account provided for your pilot workspace.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: StrivoColors.muted,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.all_inclusive_rounded,
            size: 32, color: StrivoColors.coral),
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