import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../welcome/entry_role.dart';
import 'barber_session.dart';

/// The barber's way in when not signed in. A new barber starts with the code
/// from their salon owner; once the code shows their salon and name, they
/// create the account. Barbers who have one sign in instead.
class BarberStartScreen extends ConsumerStatefulWidget {
  const BarberStartScreen({super.key});

  @override
  ConsumerState<BarberStartScreen> createState() => _BarberStartScreenState();
}

class _BarberStartScreenState extends ConsumerState<BarberStartScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _minPassword = 8;
  static const _muted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signingIn = false;

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  BarberSessionNotifier get _session =>
      ref.read(barberSessionProvider.notifier);

  void _switchMode(bool signingIn) {
    _session.clearInvite();
    _formKey.currentState?.reset();
    setState(() => _signingIn = signingIn);
  }

  Future<void> _submit() async {
    final state = ref.read(barberSessionProvider);
    if (state.isLoading) return;
    if (!_signingIn && state.invite == null) {
      await _session.checkCode(_code.text);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_signingIn) {
      await _session.login(email: _email.text, password: _password.text);
    } else {
      await _session.registerWithCode(
        email: _email.text,
        password: _password.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(barberSessionProvider);
    final invite = state.invite;

    final (title, subtitle, action) = _signingIn
        ? (
            'Barber sign in',
            'Your agenda, your earnings, your portfolio',
            'Sign in',
          )
        : invite == null
        ? (
            'Enter your salon code',
            'Your salon owner gives it to you: Team → your name → '
                'Invite to the app.',
            'Continue',
          )
        : (
            'Create your account',
            'You will sign in with this email and password.',
            'Create account and join',
          );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () {
                          _session.clearInvite();
                          ref.read(entryRoleProvider.notifier).reset();
                        },
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Who are you?'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.content_cut,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    if (state.errorMessage != null)
                      _Notice(state.errorMessage!, error: true),
                    if (state.infoMessage != null) _Notice(state.infoMessage!),
                    if (!_signingIn && invite == null) _codeField(),
                    if (!_signingIn && invite != null) ...[
                      _InviteCard(
                        shopName: invite.shopName,
                        barberName: invite.barberName,
                        onChangeCode: _session.clearInvite,
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_signingIn || invite != null) ..._credentialFields(),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: state.isLoading ? null : _submit,
                      child: state.isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(action),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => _switchMode(!_signingIn),
                      child: Text(
                        _signingIn
                            ? 'New here? Start with your salon code'
                            : 'Already have an account? Sign in',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeField() {
    return TextField(
      controller: _code,
      autofocus: true,
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.characters,
      maxLength: 8,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
        TextInputFormatter.withFunction(
          (_, value) => value.copyWith(text: value.text.toUpperCase()),
        ),
      ],
      onSubmitted: (_) => _submit(),
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: 6,
      ),
      decoration: const InputDecoration(hintText: 'ABCD2345', counterText: ''),
    );
  }

  List<Widget> _credentialFields() => [
    TextFormField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      decoration: const InputDecoration(
        labelText: 'Email Address',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (v) {
        final value = v?.trim() ?? '';
        if (value.isEmpty) return 'Please enter an email';
        if (!_emailPattern.hasMatch(value)) {
          return 'Enter a valid email address';
        }
        return null;
      },
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: _password,
      obscureText: true,
      autofillHints: _signingIn
          ? const [AutofillHints.password]
          : const [AutofillHints.newPassword],
      onFieldSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        labelText: 'Password',
        prefixIcon: Icon(Icons.lock_outline),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Please enter your password';
        if (!_signingIn && v.length < _minPassword) {
          return 'Password must be at least $_minPassword characters';
        }
        return null;
      },
    ),
  ];
}

/// "You are joining Blade & Crown as Sami".
class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.shopName,
    required this.barberName,
    required this.onChangeCode,
  });

  final String shopName;
  final String barberName;
  final VoidCallback onChangeCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOU ARE JOINING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFF166534),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            shopName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.black,
                child: Text(
                  barberName.isEmpty ? '?' : barberName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      barberName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'The name your salon registered. You can ask for a '
                      'change later; your owner approves it.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onChangeCode,
              child: const Text('Not you? Use another code'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: error ? const Color(0xFFF87171) : const Color(0xFF34D399),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
          fontSize: 13,
        ),
      ),
    );
  }
}
