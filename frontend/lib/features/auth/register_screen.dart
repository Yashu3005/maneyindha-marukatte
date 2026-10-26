import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../theme/app_theme.dart';
import '../onboarding/onboarding_screens.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'customer';
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    if (name.length < 2) {
      setState(() => _error = 'Please enter your full name');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).register(
            name,
            email,
            password,
            role: _role,
          );
      if (mounted) {
        context.go(_role == 'entrepreneur' ? '/seller' : '/app');
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
      title: 'Create Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Join Maneyindha Marukatte', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Create an account to start buying or selling homemade creations.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 24),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'customer',
                label: Text('Customer (Buy)'),
                icon: Icon(Icons.shopping_bag_outlined, size: 18),
              ),
              ButtonSegment(
                value: 'entrepreneur',
                label: Text('Seller (Sell)'),
                icon: Icon(Icons.storefront_outlined, size: 18),
              ),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              hintText: 'e.g. Yashaswini Rao',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'Must be at least 8 characters',
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
            label: 'Create Account',
            busy: _busy,
            onTap: _submit,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Already have an account? ', style: sans(14, color: MMColors.textSecondary)),
              GestureDetector(
                onTap: () => context.push('/login'),
                child: Text(
                  'Sign In',
                  style: sans(14, weight: FontWeight.w700, color: MMColors.deepOlive),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
