import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/repositories.dart';
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
    setState(() { _busy = true; _error = null; });
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
        _category != null && _years != null && _address.text.trim().isNotEmpty;
    return OliveScaffold(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text('Business Information', style: serif(24, color: MMColors.cream))),
        const SizedBox(height: 24),
        Text('Business Name:', style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 6),
        TextField(controller: _name, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Enter your business name')),
        const SizedBox(height: 16),
        Text('Business Category:', style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _category,
          hint: const Text('Select Category'),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: 16),
        Text('Years Of Experience:', style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _years,
          hint: const Text('Select Experience'),
          items: _experience.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _years = v),
        ),
        const SizedBox(height: 16),
        Text('Address:', style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 6),
        TextField(controller: _address, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Enter your Address')),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.amberAccent)),
        ],
        const SizedBox(height: 28),
        CreamButton(label: _busy ? 'Saving…' : 'Next', onTap: (ready && !_busy) ? _next : null),
      ]),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Consumer(builder: (ctx2, ref2, _) {
              final photos = ref2.watch(imagesProvider(query));
              return photos.when(
                loading: () => const SizedBox(
                    height: 160, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => const SizedBox(
                    height: 100, child: Center(child: Text('Could not load images'))),
                data: (urls) => Wrap(
                  spacing: 8, runSpacing: 8,
                  children: urls
                      .map((u) => GestureDetector(
                            onTap: () => Navigator.pop(ctx, u),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(u, width: 110, height: 110, fit: BoxFit.cover),
                            ),
                          ))
                      .toList(),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _uploadTile(String label, String? value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
          const SizedBox(height: 6),
          Material(
            color: MMColors.cream,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                width: double.infinity, height: 82,
                child: value == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.upload_outlined, color: MMColors.deepOlive),
                        Text('Upload File', style: serif(14, weight: FontWeight.w400)),
                      ])
                    : Row(children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          child: Image.network(value, width: 82, height: 82, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.check_circle, color: MMColors.deepOlive),
                        const SizedBox(width: 6),
                        Text('Uploaded', style: serif(14)),
                      ]),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ready = _idUrl != null && _proofUrl != null && _photoUrl != null;
    return OliveScaffold(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text('Upload Documents', style: serif(24, color: MMColors.cream))),
        const SizedBox(height: 20),
        Text('Identity Type:', style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _identityType,
          items: _identityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _identityType = v ?? _identityType),
        ),
        const SizedBox(height: 18),
        _uploadTile('$_identityType / ID Proof', _idUrl, () async {
          final u = await _pick('identity card document');
          if (u != null) setState(() => _idUrl = u);
        }),
        _uploadTile('Business Proof', _proofUrl, () async {
          final u = await _pick('business certificate document');
          if (u != null) setState(() => _proofUrl = u);
        }),
        _uploadTile('Business Profile Photo', _photoUrl, () async {
          final u = await _pick('woman small business shop');
          if (u != null) setState(() => _photoUrl = u);
        }),
        const SizedBox(height: 8),
        CreamButton(
          label: 'Next',
          onTap: !ready ? null : () {
            final data = Map<String, dynamic>.from(ref.read(sellerOnboardingProvider));
            data['identityType'] = _identityType;
            data['idUrl'] = _idUrl;
            data['proofUrl'] = _proofUrl;
            data['photoUrl'] = _photoUrl;
            ref.read(sellerOnboardingProvider.notifier).state = data;
            context.push('/seller/onboarding/review');
          },
        ),
      ]),
    );
  }
}

// ---------------- Step 3: Review + terms → Submit ----------------
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text('$label:', style: serif(14))),
          Expanded(child: Text(value ?? '-', style: serif(14, weight: FontWeight.w400))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final data = ref.watch(sellerOnboardingProvider);
    return OliveScaffold(
      child: Column(children: [
        Text('Review Your Details', style: serif(24, color: MMColors.cream)),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MMColors.cream,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            _row('Name', auth.name),
            _row('Business', data['businessName']?.toString()),
            _row('Category', data['category']?.toString()),
            _row('Experience', data['years']?.toString()),
            _row('Address', data['address']?.toString()),
            _row('Identity', data['identityType']?.toString()),
          ]),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          checkColor: MMColors.deepOlive,
          activeColor: MMColors.cream,
          title: Text('I agree to the terms and conditions',
              style: serif(14, weight: FontWeight.w400, color: MMColors.cream)),
        ),
        const SizedBox(height: 12),
        CreamButton(
            label: _busy ? 'Submitting…' : 'Submit',
            onTap: (_agreed && !_busy) ? _submit : null),
      ]),
    );
  }
}

// ---------------- Step 4: Submitted + Status ----------------
class SubmittedScreen extends StatelessWidget {
  const SubmittedScreen({super.key});
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
        Text('Application Submitted!!!', style: serif(24, color: MMColors.cream)),
        const SizedBox(height: 12),
        Text(
          'Your entrepreneur application has been\nsubmitted successfully.\n\nYou will be notified once approved\nby our team.',
          textAlign: TextAlign.center,
          style: serif(15, weight: FontWeight.w400, color: MMColors.cream),
        ),
        const SizedBox(height: 32),
        CreamButton(label: 'View Status',
            onTap: () => context.go('/seller/onboarding/status')),
      ]),
    );
  }
}

class ApplicationStatusScreen extends ConsumerWidget {
  const ApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(myBusinessesProvider);
    return OliveScaffold(
      child: businesses.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: MMColors.cream)),
        error: (e, _) => Text(apiError(e), style: serif(14, color: MMColors.cream)),
        data: (shops) {
          final status = shops.isEmpty
              ? 'pending'
              : ((shops.first['verification'] as Map?)?['status']?.toString() ?? 'pending');
          final approved = status == 'approved';
          return Column(children: [
            Text('Application Status', style: serif(24, color: MMColors.cream)),
            const SizedBox(height: 32),
            CircleAvatar(
              radius: 40,
              backgroundColor: MMColors.cream,
              child: Icon(
                approved ? Icons.verified : Icons.hourglass_top,
                size: 42, color: MMColors.deepOlive,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              approved
                  ? 'Congratulations!\nYour entrepreneur account\nhas been approved.'
                  : 'Status: ${status.replaceAll('_', ' ')}\nOur team is reviewing your application.',
              textAlign: TextAlign.center,
              style: serif(16, weight: FontWeight.w400, color: MMColors.cream),
            ),
            const SizedBox(height: 32),
            CreamButton(
                label: 'Continue — Create credentials',
                onTap: () => context.go('/seller/onboarding/credentials')),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => ref.invalidate(myBusinessesProvider),
              child: Text('Refresh status',
                  style: serif(14, weight: FontWeight.w400, color: MMColors.cream)),
            ),
          ]);
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
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authProvider.notifier)
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
    return OliveScaffold(
      child: Column(children: [
        Text('Became an Entrepreneur', style: serif(24, color: MMColors.cream)),
        const SizedBox(height: 28),
        Text('Create your credentials',
            style: serif(18, weight: FontWeight.w400, color: MMColors.cream)),
        const SizedBox(height: 16),
        TextField(controller: _username, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline),
                hintText: 'UserName (Unique)')),
        const SizedBox(height: 14),
        TextField(controller: _password, obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.lock_outline), hintText: 'Password')),
        const SizedBox(height: 14),
        TextField(controller: _confirm, obscureText: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.lock_outline), hintText: 'Confirm Password')),
        const SizedBox(height: 6),
        Text('Password must be at least 6 characters',
            style: serif(12, weight: FontWeight.w400, color: MMColors.cream)),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.amberAccent)),
        ],
        const SizedBox(height: 24),
        CreamButton(label: _busy ? 'Saving…' : 'Next', onTap: (ready && !_busy) ? _next : null),
      ]),
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
    'Village Name': 'Enter your village name',
    'Friend Name': 'Enter your best friend name',
    'Food Name': 'Enter your favourite food name',
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controllers.values.every((c) => c.text.trim().isNotEmpty);
    return OliveScaffold(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text('Security Questions', style: serif(24, color: MMColors.cream))),
        const SizedBox(height: 20),
        for (final entry in _controllers.entries) ...[
          Text(entry.key,
              style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
          const SizedBox(height: 6),
          TextField(
            controller: entry.value,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: _hints[entry.key]),
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 10),
        CreamButton(label: _busy ? 'Saving…' : 'Next', onTap: (ready && !_busy) ? _next : null),
      ]),
    );
  }
}
