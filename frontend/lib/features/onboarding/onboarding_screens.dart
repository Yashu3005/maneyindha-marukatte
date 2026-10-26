import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../theme/app_theme.dart';
import '../../shared/mm_logo.dart';

/// Responsive Scaffold with warm modern Indian aesthetics.
/// Displays a split view on Desktop/Tablet and a clean centered view on Mobile.
class ModernScaffold extends StatelessWidget {
  final Widget child;
  final bool showBack;
  final String? title;
  final String? subtitle;

  const ModernScaffold({
    super.key,
    required this.child,
    this.showBack = true,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 860;

    return Scaffold(
      backgroundColor: MMColors.paper,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: (showBack && context.canPop())
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => context.pop(),
                tooltip: 'Back',
              )
            : null,
        title: title != null ? Text(title!, style: serif(18, weight: FontWeight.w700)) : null,
        centerTitle: true,
      ),
      body: SafeArea(
        child: isWide
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: MMColors.borderLight, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          // Left Brand & Storytelling Panel
                          Expanded(
                            flex: 5,
                            child: Container(
                              color: MMColors.deepOlive,
                              padding: const EdgeInsets.all(36),
                              child: Center(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: MMColors.cream,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const MMLogo(size: 56),
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        'MANEYINDHA\nMARUKATTE',
                                        style: serif(28, color: MMColors.cream, height: 1.15),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'From home kitchens and craft rooms to your doorstep.',
                                        style: sans(14, color: MMColors.sage, height: 1.4),
                                      ),
                                      const SizedBox(height: 28),
                                      _featurePill(Icons.bakery_dining_outlined, 'Home-made Freshness'),
                                      const SizedBox(height: 12),
                                      _featurePill(Icons.handyman_outlined, 'Authentic Handicrafts'),
                                      const SizedBox(height: 12),
                                      _featurePill(Icons.verified_user_outlined, 'Verified Women Sellers'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Right Interactive Form Card
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(40),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: child,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _featurePill(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: MMColors.olive,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: MMColors.cream, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: sans(14, color: MMColors.cream, weight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.busy = false,
    this.color,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? MMColors.deepOlive,
          foregroundColor: textColor ?? MMColors.cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(label, style: sans(16, weight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}

// ---------------- 1. Landing Screen ----------------
class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return ModernScaffold(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand Wordmark
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MMColors.cream,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: MMColors.borderLight),
              ),
              child: Column(
                children: [
                  const MMLogo(size: 72),
                  const SizedBox(height: 12),
                  Text('MANEYINDHA', style: serif(24, weight: FontWeight.w800)),
                  Text('MARUKATTE', style: serif(24, weight: FontWeight.w800, color: MMColors.terracotta)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Made nearby, with love 🌸',
              style: serif(18, weight: FontWeight.w600, color: MMColors.deepOlive),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Empowering home-based women entrepreneurs across India to share authentic culinary and artisan treasures.',
              textAlign: TextAlign.center,
              style: sans(14, color: MMColors.textSecondary, height: 1.4),
            ),
          ),
          const SizedBox(height: 36),
          PrimaryButton(
            label: 'Get Started',
            icon: Icons.arrow_forward_rounded,
            onTap: () => context.push('/onboarding/email'),
          ),
          if (auth.isLoggedIn) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_rounded, size: 18),
              label: Text('Continue as ${auth.name}'),
              onPressed: () {
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
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Already have a password? ', style: sans(14, color: MMColors.textSecondary)),
              GestureDetector(
                onTap: () => context.push('/login'),
                child: Text(
                  'Sign In',
                  style: sans(14, weight: FontWeight.w700, color: MMColors.deepOlive),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Browse marketplace without account'),
              onPressed: () => context.go('/app'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 2. Email Screen ----------------
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
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).sendOtp(email);
      if (mounted) {
        context.push(
          '/onboarding/otp',
          extra: {'email': email},
        );
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
      title: 'Welcome',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter your Email', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'We will send you a one-time verification code to sign in or register your account.',
            style: sans(14, color: MMColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
            onSubmitted: (_) => _send(),
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
            label: 'Send Verification Code',
            busy: _busy,
            onTap: _send,
          ),
        ],
      ),
    );
  }
}

// ---------------- 3. OTP Screen ----------------
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
  int _cooldownSeconds = 60;
  int _expirySeconds = 300; // 5-minute countdown UI aid
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    _timer?.cancel();
    setState(() {
      _cooldownSeconds = 60;
      _expirySeconds = 300;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds > 0) _cooldownSeconds--;
        if (_expirySeconds > 0) _expirySeconds--;
      });
      if (_cooldownSeconds == 0 && _expirySeconds == 0) {
        timer.cancel();
      }
    });
  }

  String _formatExpiry() {
    final mins = _expirySeconds ~/ 60;
    final secs = _expirySeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final isNew = await ref.read(authProvider.notifier).verifyOtp(widget.email, code);
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

  Future<void> _resend() async {
    if (_cooldownSeconds > 0 || _busy) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.email);
      _startCooldownTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A fresh 6-digit verification code has been sent')),
        );
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
      title: 'Verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Verify your Email', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: sans(14, color: MMColors.textSecondary, height: 1.4),
              children: [
                const TextSpan(text: 'We sent a 6-digit verification code to\n'),
                TextSpan(
                  text: widget.email,
                  style: sans(14, weight: FontWeight.w700, color: MMColors.deepOlive),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofocus: true,
            style: serif(28, weight: FontWeight.w700, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: serif(28, color: MMColors.textMuted, letterSpacing: 8),
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _expirySeconds > 0 ? MMColors.sageLight : const Color(0xFFFFECEC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _expirySeconds > 0 ? MMColors.sage : const Color(0xFFF5B5B5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: _expirySeconds > 0 ? MMColors.deepOlive : const Color(0xFFBA1A1A),
                ),
                const SizedBox(width: 8),
                Text(
                  _expirySeconds > 0
                      ? 'Code expires in ${_formatExpiry()} · Check spam if needed'
                      : 'Verification code has expired. Please resend a new code.',
                  style: sans(
                    12,
                    weight: FontWeight.w600,
                    color: _expirySeconds > 0 ? MMColors.deepOlive : const Color(0xFFBA1A1A),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
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
            label: 'Verify & Continue',
            busy: _busy,
            onTap: _verify,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  _cooldownSeconds > 0
                      ? 'Resend Code in ${_cooldownSeconds}s'
                      : 'Resend Code',
                ),
                onPressed: (_cooldownSeconds > 0 || _busy) ? null : _resend,
              ),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: MMColors.textMuted)),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Change Email'),
                onPressed: _busy ? null : () => context.pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------- 4. Profile Setup Screen ----------------
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
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final address = _address.text.trim();

    if (name.length < 2) {
      setState(() => _error = 'Please enter your full name');
      return;
    }
    if (phone.length < 10) {
      setState(() => _error = 'Please enter a valid 10-digit phone number');
      return;
    }
    if (address.isEmpty) {
      setState(() => _error = 'Please enter your address for delivery');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).updateProfile({
        'name': name,
        'phone': phone,
        'avatarUrl': _avatarUrl ?? 'https://picsum.photos/seed/user-avatar/200/200',
        'addresses': [
          {'label': 'Home', 'line1': address}
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

    return ModernScaffold(
      title: 'Profile Setup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Complete Your Profile', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Tell us your name and where we can deliver delicious treats to you.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: MMColors.sage,
                  backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                  child: _avatarUrl == null
                      ? const Icon(Icons.person_rounded, size: 48, color: MMColors.deepOlive)
                      : null,
                ),
                if (_avatarUrl != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: MMColors.deepOlive,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select your avatar:',
            style: sans(13, weight: FontWeight.w600, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: photos.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: MMColors.deepOlive),
                ),
              ),
              error: (e, _) => const SizedBox(),
              data: (urls) => ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final isSelected = _avatarUrl == urls[i];
                  return GestureDetector(
                    onTap: () => setState(() => _avatarUrl = urls[i]),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? MMColors.terracotta : MMColors.border,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundImage: NetworkImage(urls[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              hintText: 'e.g. Ananya Rao',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: '9876543210',
              prefixIcon: Icon(Icons.phone_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Delivery Address',
              hintText: 'House / Flat number, Street, Area, Bengaluru',
              prefixIcon: Icon(Icons.location_on_outlined, size: 20),
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
            label: 'Save & Continue',
            busy: _busy,
            onTap: _continue,
          ),
        ],
      ),
    );
  }
}

// ---------------- 5. Role Selection Screen ----------------
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
        final hasBusiness = await ref.read(authProvider.notifier).switchRole('entrepreneur');
        ref.invalidate(myBusinessesProvider);
        if (mounted) {
          context.go(hasBusiness ? '/seller' : '/seller/onboarding/business');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _roleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String choice,
    bool recommended = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: MMColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: recommended ? MMColors.terracotta : MMColors.borderLight,
            width: recommended ? 1.8 : 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : () => _pick(choice),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: recommended ? MMColors.terracottaLight : MMColors.sageLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: recommended ? MMColors.terracotta : MMColors.deepOlive,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: serif(18, weight: FontWeight.w700)),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: MMColors.terracotta,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'SELLER',
                                style: sans(10, weight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: sans(13, color: MMColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: MMColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModernScaffold(
      title: 'Your Intent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How would you like to join?', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Choose your primary activity. You can change this anytime from your profile.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _roleCard(
            title: 'Customer',
            subtitle: 'I want to discover and purchase homemade food, cakes, and handicrafts.',
            icon: Icons.shopping_bag_outlined,
            choice: 'customer',
          ),
          _roleCard(
            title: 'Women Entrepreneur',
            subtitle: 'I create homemade products and want to build a verified business.',
            icon: Icons.storefront_rounded,
            choice: 'entrepreneur',
            recommended: true,
          ),
          _roleCard(
            title: 'Both (Buy & Sell)',
            subtitle: 'I want to sell my creations and also order from nearby women entrepreneurs.',
            icon: Icons.sync_alt_rounded,
            choice: 'both',
          ),
        ],
      ),
    );
  }
}

// ---------------- 6. Customer Success Screen ----------------
class CustomerSuccessScreen extends StatelessWidget {
  const CustomerSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ModernScaffold(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: MMColors.sageLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.celebration_rounded,
                size: 52,
                color: MMColors.deepOlive,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome to the Family! 🌸',
            textAlign: TextAlign.center,
            style: serif(26, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Your account is ready. Discover authentic home-cooked delicacies, customized cakes, and artisanal treasures from trusted women entrepreneurs near you.',
            textAlign: TextAlign.center,
            style: sans(15, color: MMColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 40),
          PrimaryButton(
            label: 'Explore Marketplace Now',
            icon: Icons.shopping_bag_outlined,
            onTap: () => context.go('/app'),
          ),
        ],
      ),
    );
  }
}
