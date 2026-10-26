import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../theme/app_theme.dart';
import '../onboarding/onboarding_screens.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final identity = _identity.text.trim();
    final password = _password.text;

    if (identity.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your username/email and password');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).login(identity, password);
      ref.invalidate(myBusinessesProvider);
      ref.invalidate(ordersProvider);
      ref.invalidate(cartProvider);
      if (mounted) {
        final auth = ref.read(authProvider);
        if (auth.isAdmin) {
          context.go('/admin');
        } else if (auth.isEntrepreneur) {
          context.go('/seller');
        } else {
          context.go('/app');
        }
      }
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModernScaffold(
      title: 'Sign In',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Welcome Back', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Sign in using your email, username, or registered phone.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _identity,
            decoration: const InputDecoration(
              labelText: 'Email or Username',
              hintText: 'e.g. ananya@domain.com or ananya',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: MMColors.textMuted,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFECEC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5B5B5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Color(0xFFBA1A1A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: sans(13, color: const Color(0xFFBA1A1A))),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Sign In',
            busy: _busy,
            onTap: _submit,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Don't have an account? ", style: sans(14, color: MMColors.textSecondary)),
              GestureDetector(
                onTap: () => context.push('/register'),
                child: Text(
                  'Register',
                  style: sans(14, weight: FontWeight.w700, color: MMColors.deepOlive),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.email_outlined, size: 16),
              label: const Text('Sign in with Email OTP instead'),
              onPressed: () => context.push('/onboarding/email'),
            ),
          ),
        ],
      ),
    );
  }
}
