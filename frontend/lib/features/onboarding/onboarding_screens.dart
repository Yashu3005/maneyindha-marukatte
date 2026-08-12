import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../theme/app_theme.dart';
import '../../shared/mm_logo.dart';

/// Shared olive canvas used across the Figma onboarding flow.
class OliveScaffold extends StatelessWidget {
  final Widget child;
  final bool showBack;
  const OliveScaffold({super.key, required this.child, this.showBack = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MMColors.olive,
      body: SafeArea(
        child: Stack(children: [
          if (showBack && context.canPop())
            Positioned(
              top: 8, left: 8,
              child: Material(
                color: MMColors.sage,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => context.pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.chevron_left, color: MMColors.deepOlive),
                  ),
                ),
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: child,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class CreamButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const CreamButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: onTap == null ? MMColors.cream.withOpacity(0.5) : MMColors.cream,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text(label, style: serif(20))),
          ),
        ),
      ),
    );
  }
}

Widget wordmark({double size = 30, Color color = Colors.white}) => Column(children: [
      MMLogo(size: size * 2.6),
      const SizedBox(height: 10),
      Text('MANEYINDHA', style: serif(size, color: color)),
      Text('MARUKATTE', style: serif(size, color: color)),
    ]);

// ---------------- 1. Landing ----------------
class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return OliveScaffold(
      showBack: false,
      child: Column(children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: MMColors.cream,
            borderRadius: BorderRadius.circular(20),
          ),
          child: wordmark(color: MMColors.deepOlive),
        ),
        const SizedBox(height: 12),
        Text('Made nearby, with love',
            style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 48),
        CreamButton(
            label: 'Get Started',
            onTap: () => context.push('/onboarding/email')),
        if (auth.isLoggedIn) ...[
          const SizedBox(height: 12),
          CreamButton(
            label: 'Continue as ${auth.name}',
            onTap: () {
              if (auth.isAdmin) {
                context.go('/admin');
              } else if (auth.isEntrepreneur) {
                context.go('/seller');
              } else {
                context.go('/app');
              }
            },
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.push('/login'),
          child: Text('Sign in with password',
              style: serif(14, weight: FontWeight.w400, color: MMColors.cream)),
        ),
      ]),
    );
  }
}

// ---------------- 2 + 3. Email → OTP ----------------
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});
  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    setState(() { _busy = true; _error = null; });
    try {
      final demo = await ref.read(authProvider.notifier).sendOtp(_email.text.trim());
      if (mounted) {
        context.push('/onboarding/otp',
            extra: {'email': _email.text.trim(), 'demoOtp': demo});
      }
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OliveScaffold(
      child: Column(children: [
        wordmark(size: 22),
        const SizedBox(height: 48),
        Text('Enter your e-mail:',
            style: serif(18, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.amberAccent)),
        ],
        const SizedBox(height: 24),
        CreamButton(label: _busy ? 'Sending…' : 'Send OTP', onTap: _busy ? null : _send),
      ]),
    );
  }
}

class OtpScreen extends ConsumerStatefulWidget {
  final String email;
  final String? demoOtp;
  const OtpScreen({super.key, required this.email, this.demoOtp});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otp = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    setState(() { _busy = true; _error = null; });
    try {
      final isNew = await ref
          .read(authProvider.notifier)
          .verifyOtp(widget.email, _otp.text.trim());
      final auth = ref.read(authProvider);
      if (!mounted) return;
      if (isNew || !auth.profileComplete) {
        context.go('/onboarding/profile');
      } else if (auth.isEntrepreneur) {
        context.go('/seller');
      } else {
        context.go('/app');
      }
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OliveScaffold(
      child: Column(children: [
        wordmark(size: 22),
        const SizedBox(height: 40),
        Text('Enter the OTP:',
            style: serif(18, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 12),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: serif(24),
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 8),
        Text('Demo OTP: ${widget.demoOtp ?? '029403'}',
            style: serif(14, weight: FontWeight.w400, color: MMColors.cream)),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.amberAccent)),
        ],
        const SizedBox(height: 24),
        CreamButton(label: _busy ? 'Verifying…' : 'Continue', onTap: _busy ? null : _verify),
      ]),
    );
  }
}

// ---------------- 4. Create your Profile ----------------
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String? _avatarUrl;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    if (_avatarUrl == null) {
      setState(() => _error = 'Please choose a profile photo');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).updateProfile({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'avatarUrl': _avatarUrl,
        'addresses': [
          {'label': 'Home', 'line1': _address.text.trim()}
        ],
      });
      if (mounted) context.go('/onboarding/role');
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(imagesProvider('woman portrait smile'));
    final ready = _name.text.trim().length >= 2 &&
        _phone.text.trim().length >= 10 &&
        _address.text.trim().isNotEmpty;
    return OliveScaffold(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Text('Create your Profile', style: serif(24, color: MMColors.cream))),
        const SizedBox(height: 20),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: MMColors.deepOlive,
            backgroundImage: _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
            child: _avatarUrl == null
                ? const Icon(Icons.camera_alt, color: MMColors.cream)
                : null,
          ),
        ),
        const SizedBox(height: 10),
        Text('Choose your photo (required):',
            style: serif(14, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: photos.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: MMColors.cream)),
            error: (e, _) => Text('Could not load photos',
                style: serif(12, color: MMColors.cream)),
            data: (urls) => ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() => _avatarUrl = urls[i]),
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: NetworkImage(urls[i]),
                  child: _avatarUrl == urls[i]
                      ? const CircleAvatar(
                          radius: 12,
                          backgroundColor: MMColors.deepOlive,
                          child: Icon(Icons.check, size: 14, color: MMColors.cream))
                      : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: _name, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline), hintText: 'Enter Full Name')),
        const SizedBox(height: 12),
        TextField(controller: _phone, onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.phone_outlined), hintText: 'Enter Phone Number')),
        const SizedBox(height: 12),
        TextField(controller: _address, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined), hintText: 'Enter Address')),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.amberAccent)),
        ],
        const SizedBox(height: 24),
        CreamButton(
            label: _busy ? 'Saving…' : 'Continue',
            onTap: (ready && !_busy) ? _continue : null),
      ]),
    );
  }
}

// ---------------- 5. What do you wish to be? ----------------
class RoleScreen extends ConsumerStatefulWidget {
  const RoleScreen({super.key});
  @override
  ConsumerState<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends ConsumerState<RoleScreen> {
  bool _busy = false;

  Future<void> _pick(String choice) async {
    setState(() => _busy = true);
    try {
      if (choice == 'customer') {
        await ref.read(authProvider.notifier).switchRole('customer');
        if (mounted) context.go('/onboarding/success');
      } else {
        // Entrepreneur and Both begin the seller journey (they can shop too).
        final hasBusiness = await ref
            .read(authProvider.notifier)
            .switchRole('entrepreneur');
        ref.invalidate(myBusinessesProvider);
        if (mounted) {
          context.go(hasBusiness ? '/seller' : '/seller/onboarding/business');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _roleCard(String title, String subtitle, String choice) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Material(
          color: MMColors.cream,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : () => _pick(choice),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(title, style: serif(24)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: serif(15, weight: FontWeight.w400)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return OliveScaffold(
      child: Column(children: [
        wordmark(size: 20),
        const SizedBox(height: 24),
        Text('What do you wish to be?', style: serif(24, color: MMColors.cream)),
        const SizedBox(height: 28),
        _roleCard('Customer', 'I want to buy Products', 'customer'),
        _roleCard('Women Entrepreneur', 'I want to sell products', 'entrepreneur'),
        _roleCard('Both', 'I want to buy and sell Products', 'both'),
        const SizedBox(height: 8),
        Text('Note: You can change this later\nfrom your profile section',
            textAlign: TextAlign.center,
            style: serif(15, weight: FontWeight.w400, color: MMColors.cream)),
      ]),
    );
  }
}

// ---------------- 6. Customer success ----------------
class CustomerSuccessScreen extends StatelessWidget {
  const CustomerSuccessScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return OliveScaffold(
      showBack: false,
      child: Column(children: [
        const CircleAvatar(
          radius: 44,
          backgroundColor: MMColors.cream,
          child: Icon(Icons.check_rounded, size: 52, color: MMColors.deepOlive),
        ),
        const SizedBox(height: 24),
        Text('Your registration is successful!',
            textAlign: TextAlign.center, style: serif(22, color: MMColors.cream)),
        const SizedBox(height: 8),
        Text('Discover home-made treasures\nfrom women near you.',
            textAlign: TextAlign.center,
            style: serif(15, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 40),
        CreamButton(label: 'Explore Now', onTap: () => context.go('/app')),
      ]),
    );
  }
}
