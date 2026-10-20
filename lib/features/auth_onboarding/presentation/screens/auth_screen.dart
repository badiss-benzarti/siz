import 'package:siz/core/demo/demo_seeder.dart';
import 'package:siz/core/repositories/shop_repository.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/welcome/entry_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  bool _isRegistering = false;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () =>
                          ref.read(entryRoleProvider.notifier).reset(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Who are you?'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // App Icon / Logo
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
                    _isRegistering
                        ? 'Create Owner Account'
                        : 'Barber Shop Owner Portal',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegistering
                        ? 'Set up your master account to manage your shop'
                        : 'Sign in to access your floor plan and financial ledger',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (authState.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF87171)),
                      ),
                      child: Text(
                        authState.errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontSize: 13,
                        ),
                      ),
                    ),

                  if (authState.infoMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF34D399)),
                      ),
                      child: Text(
                        authState.infoMessage!,
                        style: const TextStyle(
                          color: Color(0xFF065F46),
                          fontSize: 13,
                        ),
                      ),
                    ),

                  if (_isRegistering) ...[
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Your Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter your full name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter an email';
                      }
                      if (!_emailPattern.hasMatch(val.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    autofillHints: _isRegistering
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (_isRegistering &&
                          val.length < ShopRepository.minPasswordLength) {
                        return 'Password must be at least '
                            '${ShopRepository.minPasswordLength} characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _submit,
                    child: authState.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isRegistering
                                ? 'Register as Shop Owner'
                                : 'Sign In to Shop',
                          ),
                  ),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      ref.read(authProvider.notifier).clearError();
                      _formKey.currentState?.reset();
                      setState(() {
                        _isRegistering = !_isRegistering;
                      });
                    },
                    child: Text(
                      _isRegistering
                          ? 'Already have an owner account? Sign In'
                          : 'New shop owner? Create an account',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (!_isRegistering) ...[
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'or',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Explore the demo shop'),
                      onPressed: authState.isLoading
                          ? null
                          : () => ref.read(authProvider.notifier).loginDemo(),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sample shop with a month of sales. '
                      'Sign in later with ${DemoSeeder.email} / ${DemoSeeder.password}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (ref.read(authProvider).isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    if (_isRegistering) {
      await ref
          .read(authProvider.notifier)
          .register(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            fullName: _nameCtrl.text.trim(),
          );
      // Email confirmation pending: come back to sign in afterwards.
      if (mounted && ref.read(authProvider).infoMessage != null) {
        _passwordCtrl.clear();
        setState(() => _isRegistering = false);
      }
    } else {
      await ref
          .read(authProvider.notifier)
          .login(email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
    }
  }
}
