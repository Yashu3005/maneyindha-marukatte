import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _password.text);
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
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('🌸 Maneyindha Marukatte',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Made nearby, with love',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              TextField(controller: _email,
                  decoration: const InputDecoration(labelText: 'Email or username')),
              const SizedBox(height: 12),
              TextField(controller: _password, obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Password')),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Signing in…' : 'Sign in'),
                )),
              TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('New here? Create an account'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
