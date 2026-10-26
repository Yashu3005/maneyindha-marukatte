import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';
import '../onboarding/onboarding_screens.dart';

const _categories = ['Baking', 'Handicrafts', 'Tiffin Center', 'Tailoring', 'Boutique', 'Others'];
const _experience = ['< 1 year', '1-3 years', '3-5 years', '5+ years'];
const _identityTypes = ['Aadhaar', 'Voter ID', 'Driving License', 'Passport'];

// ---------------- Step 1: Business Information ----------------
class BusinessInfoScreen extends ConsumerStatefulWidget {
  const BusinessInfoScreen({super.key});
  @override
  ConsumerState<BusinessInfoScreen> createState() => _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends ConsumerState<BusinessInfoScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  String? _category;
  String? _years;
  bool _busy = false;
  String? _error;

  Future<void> _next() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ApiClient.dio.post('/businesses', data: {
        'name': _name.text.trim(),
        'category': _category,
        'yearsOfExperience': _years,
        'description': '$_category business by ${ref.read(authProvider).name}',
        'address': {'line1': _address.text.trim(), 'city': 'Bengaluru'},
      });
      final business = Map<String, dynamic>.from(res.data['data'] as Map);
      ref.invalidate(myBusinessesProvider);
      ref.read(sellerOnboardingProvider.notifier).state = {
        'businessId': business['_id'],
        'businessName': _name.text.trim(),
        'category': _category,
        'years': _years,
        'address': _address.text.trim(),
      };
      if (mounted) context.push('/seller/onboarding/documents');
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.text.trim().isNotEmpty &&
        _category != null &&
        _years != null &&
        _address.text.trim().isNotEmpty;

    return ModernScaffold(
      title: 'Business Setup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Business Information', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Step 1 of 4: Tell us about your homemade specialty and experience.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Business / Shop Name',
              hintText: 'e.g. Yashu’s Artisanal Bakes',
              prefixIcon: Icon(Icons.storefront_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _category,
            hint: const Text('Select Business Category'),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v),
            decoration: const InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(Icons.category_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _years,
            hint: const Text('Select Experience'),
            items: _experience.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _years = v),
            decoration: const InputDecoration(
              labelText: 'Years of Experience',
              prefixIcon: Icon(Icons.timeline_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _address,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Kitchen / Workshop Address',
              hintText: 'Location in Bengaluru where items are made',
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
              child: Text(_error!, style: sans(13, color: const Color(0xFFBA1A1A))),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Next — Upload Verification Proofs',
            busy: _busy,
            onTap: ready && !_busy ? _next : null,
          ),
        ],
      ),
    );
  }
}

// ---------------- Step 2: Upload Documents ----------------
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});
  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String _identityType = _identityTypes.first;
  String? _idUrl;
  String? _proofUrl;
  String? _photoUrl;

  Future<String?> _pick(String query) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Photo Sample', style: serif(18, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Pick a photo sample to attach to your verification.',
                    style: sans(13, color: MMColors.textSecondary)),
                const SizedBox(height: 16),
                Consumer(builder: (ctx2, ref2, _) {
                  final photos = ref2.watch(imagesProvider(query));
                  return photos.when(
                    loading: () => const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => const SizedBox(
                      height: 100,
                      child: Center(child: Text('Could not load sample images')),
                    ),
                    data: (urls) => Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: urls
                          .map((u) => GestureDetector(
                                onTap: () => Navigator.pop(ctx, u),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(u, width: 95, height: 95, fit: BoxFit.cover),
                                ),
                              ))
                          .toList(),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _uploadTile(String label, String? value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: sans(14, weight: FontWeight.w600, color: MMColors.textPrimary)),
            const SizedBox(height: 6),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: value == null
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_upload_outlined, color: MMColors.deepOlive),
                            const SizedBox(width: 10),
                            Text('Attach File / Photo', style: sans(14, weight: FontWeight.w600)),
                          ],
                        )
                      : Row(
                          children: [
                            ClipRRect(
                              borderRadius:
                                  const BorderRadius.horizontal(left: Radius.circular(16)),
                              child: Image.network(value, width: 80, height: 80, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 14),
                            const Icon(Icons.check_circle, color: MMColors.deepOlive),
                            const SizedBox(width: 6),
                            Text('Attached Successfully', style: sans(14, weight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ready = _idUrl != null && _proofUrl != null && _photoUrl != null;

    return ModernScaffold(
      title: 'Verification Proofs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upload Verification Proofs', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Step 2 of 4: All sellers are verified by our team to protect customer safety.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _identityType,
            items: _identityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _identityType = v ?? _identityType),
            decoration: const InputDecoration(labelText: 'Government ID Type'),
          ),
          const SizedBox(height: 18),
          _uploadTile('$_identityType Proof (Photo of ID)', _idUrl, () async {
            final u = await _pick('identity card document');
            if (u != null) setState(() => _idUrl = u);
          }),
          _uploadTile('Business / Kitchen Sample Photo', _proofUrl, () async {
            final u = await _pick('kitchen baking bakery work');
            if (u != null) setState(() => _proofUrl = u);
          }),
          _uploadTile('Entrepreneur Profile Photo', _photoUrl, () async {
            final u = await _pick('indian woman entrepreneur');
            if (u != null) setState(() => _photoUrl = u);
          }),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Next — Review Application',
            onTap: !ready
                ? null
                : () {
                    final data =
                        Map<String, dynamic>.from(ref.read(sellerOnboardingProvider));
                    data['identityType'] = _identityType;
                    data['idUrl'] = _idUrl;
                    data['proofUrl'] = _proofUrl;
                    data['photoUrl'] = _photoUrl;
                    ref.read(sellerOnboardingProvider.notifier).state = data;
                    context.push('/seller/onboarding/review');
                  },
          ),
        ],
      ),
    );
  }
}

// ---------------- Step 3: Review + Terms → Submit ----------------
class ReviewDetailsScreen extends ConsumerStatefulWidget {
  const ReviewDetailsScreen({super.key});
  @override
  ConsumerState<ReviewDetailsScreen> createState() => _ReviewDetailsScreenState();
}

class _ReviewDetailsScreenState extends ConsumerState<ReviewDetailsScreen> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _submit() async {
    final data = ref.read(sellerOnboardingProvider);
    setState(() => _busy = true);
    try {
      await ApiClient.dio.post(
        '/businesses/${data['businessId']}/verification-documents',
        data: {
          'documents': [
            {'type': 'id_proof', 'url': data['idUrl'], 'identityType': data['identityType']},
            {'type': 'business_proof', 'url': data['proofUrl']},
            {'type': 'profile_photo', 'url': data['photoUrl']},
          ],
        },
      );
      if (mounted) context.go('/seller/onboarding/submitted');
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

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label, style: sans(14, color: MMColors.textMuted)),
            ),
            Expanded(
              child: Text(value ?? '-', style: sans(14, weight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final data = ref.watch(sellerOnboardingProvider);

    return ModernScaffold(
      title: 'Review Application',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Review Your Details', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Step 3 of 4: Verify your information before submitting for admin review.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _row('Applicant Name', auth.name),
                  const Divider(height: 12),
                  _row('Business Name', data['businessName']?.toString()),
                  const Divider(height: 12),
                  _row('Category', data['category']?.toString()),
                  const Divider(height: 12),
                  _row('Experience', data['years']?.toString()),
                  const Divider(height: 12),
                  _row('Address', data['address']?.toString()),
                  const Divider(height: 12),
                  _row('ID Proof', data['identityType']?.toString()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: MMColors.deepOlive,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'I agree to adhere to home kitchen hygiene and authentic marketplace standards.',
              style: sans(13, color: MMColors.textPrimary),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Submit Application',
            busy: _busy,
            onTap: _agreed && !_busy ? _submit : null,
          ),
        ],
      ),
    );
  }
}

// ---------------- Step 4: Submitted & Application Status ----------------
class SubmittedScreen extends StatelessWidget {
  const SubmittedScreen({super.key});
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
                Icons.mark_email_read_rounded,
                size: 52,
                color: MMColors.deepOlive,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Application Submitted! 🎉',
            textAlign: TextAlign.center,
            style: serif(26, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Your entrepreneur verification has been submitted successfully.\n\nOur team verifies accounts within 24 hours. You can track status anytime.',
            textAlign: TextAlign.center,
            style: sans(14, color: MMColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 36),
          PrimaryButton(
            label: 'Check Verification Status',
            onTap: () => context.go('/seller/onboarding/status'),
          ),
        ],
      ),
    );
  }
}

class ApplicationStatusScreen extends ConsumerWidget {
  const ApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(myBusinessesProvider);

    return ModernScaffold(
      title: 'Status Tracker',
      child: businesses.when(
        loading: () => const LoadingView(message: 'Checking application status…'),
        error: (e, _) => ErrorView(message: apiError(e)),
        data: (shops) {
          final status = shops.isEmpty
              ? 'pending'
              : ((shops.first['verification'] as Map?)?['status']?.toString() ?? 'pending');
          final approved = status == 'approved';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: approved ? MMColors.sageLight : MMColors.marigoldLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    approved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                    size: 48,
                    color: approved ? MMColors.deepOlive : MMColors.marigold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                approved ? 'Congratulations! Approved 🎉' : 'Application In Review',
                textAlign: TextAlign.center,
                style: serif(24, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                approved
                    ? 'Your shop is approved and ready. Set up your login credentials to enter the Seller Dashboard.'
                    : 'Our verification team is reviewing your documents. Feel free to set your credentials below.',
                textAlign: TextAlign.center,
                style: sans(14, color: MMColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Create Seller Credentials',
                onTap: () => context.go('/seller/onboarding/credentials'),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(myBusinessesProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh Status'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------- Step 5: Credentials ----------------
class CredentialsScreen extends ConsumerStatefulWidget {
  const CredentialsScreen({super.key});
  @override
  ConsumerState<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends ConsumerState<CredentialsScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _next() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .setCredentials(_username.text.trim(), _password.text);
      if (mounted) context.go('/seller/onboarding/security');
    } catch (e) {
      setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _username.text.trim().isNotEmpty && _password.text.length >= 6;

    return ModernScaffold(
      title: 'Seller Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set Your Seller Credentials', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Create a unique username and password for quick seller login.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _username,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Shop Username (Unique)',
              hintText: 'e.g. yashubakes',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Password (min 6 characters)',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
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
              child: Text(_error!, style: sans(13, color: const Color(0xFFBA1A1A))),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Next — Security Setup',
            busy: _busy,
            onTap: ready && !_busy ? _next : null,
          ),
        ],
      ),
    );
  }
}

// ---------------- Step 6: Security Questions ----------------
class SecurityQuestionsScreen extends ConsumerStatefulWidget {
  const SecurityQuestionsScreen({super.key});
  @override
  ConsumerState<SecurityQuestionsScreen> createState() =>
      _SecurityQuestionsScreenState();
}

class _SecurityQuestionsScreenState extends ConsumerState<SecurityQuestionsScreen> {
  final _controllers = {
    'School Name': TextEditingController(),
    'Teacher Name': TextEditingController(),
    'Village Name': TextEditingController(),
    'Friend Name': TextEditingController(),
    'Food Name': TextEditingController(),
  };

  static const _hints = {
    'School Name': 'Enter your School name',
    'Teacher Name': 'Enter your favourite teacher name',
    'Village Name': 'Enter your hometown/village name',
    'Friend Name': 'Enter your best friend name',
    'Food Name': 'Enter your favourite dish name',
  };

  bool _busy = false;

  Future<void> _next() async {
    setState(() => _busy = true);
    try {
      final answers = <String, String>{};
      _controllers.forEach((k, c) => answers[k] = c.text.trim());
      await ref.read(authProvider.notifier).setSecurityQuestions(answers);
      if (mounted) context.go('/seller');
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

  @override
  Widget build(BuildContext context) {
    final ready = _controllers.values.every((c) => c.text.trim().isNotEmpty);

    return ModernScaffold(
      title: 'Account Security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Security Questions', style: serif(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'These questions help recover your seller store if you forget your password.',
            style: sans(14, color: MMColors.textSecondary),
          ),
          const SizedBox(height: 20),
          for (final entry in _controllers.entries) ...[
            Text(entry.key,
                style: sans(14, weight: FontWeight.w600, color: MMColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: entry.value,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: _hints[entry.key]),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Complete & Go to Seller Dashboard',
            busy: _busy,
            onTap: ready && !_busy ? _next : null,
          ),
        ],
      ),
    );
  }
}
