import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../services/device_location.dart';
import '../../services/repositories.dart';
import '../../theme/app_theme.dart';
import '../../shared/ui.dart';
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
  double? _lat, _lng; // only ever set from the device, after the owner taps the button
  bool _locating = false;

  Future<void> _useMyLocation() async {
    setState(() { _locating = true; _error = null; });
    final loc = await getDeviceLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (loc.isOk) { _lat = loc.lat; _lng = loc.lng; } else {
        _error = '${loc.message} You can continue without it and add it later.';
      }
    });
  }

  Future<void> _next() async {
    setState(() { _busy = true; _error = null; });
    try {
      final res = await ApiClient.dio.post('/businesses', data: {
        'name': _name.text.trim(),
        'category': _category,
        'yearsOfExperience': _years,
        'description': '$_category business by ${ref.read(authProvider).name}',
        'address': {'line1': _address.text.trim(), 'city': 'Bengaluru'},
        if (_lat != null && _lng != null) ...{
          'location': {'type': 'Point', 'coordinates': [_lng, _lat]},
          'locationSource': 'device',
        },
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
        const StepDots(current: 1, total: 3),
        const SizedBox(height: 16),
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
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: MMColors.cream),
          onPressed: _locating ? null : _useMyLocation,
          icon: _locating
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_lat == null ? Icons.my_location : Icons.check_circle_outline, size: 18),
          label: Text(_lat == null
              ? 'Use my current location (optional)'
              : 'Location added — customers nearby can find you'),
        ),
        Text(
          'Optional. Customers see your shop area only roughly (about 100 m), never your exact point.',
          style: serif(12, weight: FontWeight.w400, color: MMColors.cream),
        ),
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
// The owner's own files (PDF / JPG / PNG / WebP, up to 5 MB) go to the server, which stores them privately.
// Nothing here is a stock photo or a link: the server only accepts real uploads.
class _UploadedDoc {
  final String id;
  final String name;
  final String mime;
  final int bytes;
  const _UploadedDoc(this.id, this.name, this.mime, this.bytes);
  factory _UploadedDoc.fromJson(Map<String, dynamic> j) => _UploadedDoc(
        j['id'].toString(),
        (j['name'] ?? 'document').toString(),
        (j['mime'] ?? '').toString(),
        ((j['bytes'] ?? 0) as num).toInt(),
      );
}

String _prettySize(int b) => b >= 1024 * 1024
    ? '${(b / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(b / 1024).ceil()} KB';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});
  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  static const _maxBytes = 5 * 1024 * 1024;
  String _identityType = _identityTypes.first;
  final Map<String, _UploadedDoc> _docs = {}; // by type
  final Set<String> _busy = {};
  String? _error;
  bool _loading = true;

  String? get _businessId => ref.read(sellerOnboardingProvider)['businessId']?.toString();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// If the owner comes back to this step, show what is already uploaded.
  Future<void> _restore() async {
    final id = _businessId;
    if (id == null) { setState(() => _loading = false); return; }
    try {
      final res = await ApiClient.dio.get('/businesses/$id/documents');
      _apply((res.data['data']['documents'] as List?) ?? const []);
    } catch (_) {
      // not fatal: the owner can still upload
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(List list) {
    final next = <String, _UploadedDoc>{};
    String? idType;
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      next[m['type'].toString()] = _UploadedDoc.fromJson(m);
      if (m['type'] == 'id_proof' && m['identityType'] != null) idType = m['identityType'].toString();
    }
    if (!mounted) return;
    setState(() {
      _docs..clear()..addAll(next);
      if (idType != null && _identityTypes.contains(idType)) _identityType = idType;
    });
  }

  Future<void> _upload(String type) async {
    final businessId = _businessId;
    if (businessId == null) {
      setState(() => _error = 'Please go back and save your business details first.');
      return;
    }
    setState(() => _error = null);
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
    } catch (_) {
      setState(() => _error = 'Could not open the file picker. Please try again.');
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'That file could not be read. Please choose another.');
      return;
    }
    if (bytes.length > _maxBytes) {
      setState(() => _error = 'That file is ${_prettySize(bytes.length)}. Please choose one under 5 MB.');
      return;
    }
    setState(() => _busy.add(type));
    try {
      final form = FormData.fromMap({
        'type': type,
        if (type == 'id_proof') 'identityType': _identityType,
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      });
      final res = await ApiClient.dio.post('/businesses/$businessId/documents', data: form);
      _apply((res.data['data'] as List?) ?? const []);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(type));
    }
  }

  Future<void> _remove(String type) async {
    final doc = _docs[type];
    final businessId = _businessId;
    if (doc == null || businessId == null) return;
    setState(() { _busy.add(type); _error = null; });
    try {
      final res = await ApiClient.dio.delete('/businesses/$businessId/documents/${doc.id}');
      _apply((res.data['data'] as List?) ?? const []);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(type));
    }
  }

  /// A document stores the identity type it was uploaded under, so changing the type asks for a fresh upload.
  Future<void> _changeIdentityType(String v) async {
    if (v == _identityType) return;
    final hadId = _docs.containsKey('id_proof');
    setState(() => _identityType = v);
    if (hadId) await _remove('id_proof');
  }

  Widget _tile({
    required String type,
    required String title,
    required String hint,
    required bool mandatory,
    required IconData icon,
  }) {
    final doc = _docs[type];
    final working = _busy.contains(type);
    final isPdf = doc?.mime == 'application/pdf';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: mandatory ? MMColors.marigold : MMColors.cream.withOpacity(0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(mandatory ? 'Required' : 'Optional',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Material(
          color: MMColors.cream,
          borderRadius: BorderRadius.circular(14),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: working ? null : () => _upload(type),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: working
                  ? const SizedBox(
                      height: 56,
                      child: Center(child: SizedBox(width: 26, height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3, color: MMColors.deepOlive))))
                  : doc == null
                      ? Column(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: MMColors.sage, shape: BoxShape.circle),
                            child: Icon(icon, color: MMColors.deepOlive),
                          ),
                          const SizedBox(height: 8),
                          Text('Tap to choose a file', style: serif(15)),
                          const SizedBox(height: 2),
                          Text(hint, textAlign: TextAlign.center,
                              style: serif(12, weight: FontWeight.w400)),
                        ])
                      : Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: MMColors.sage, borderRadius: BorderRadius.circular(12)),
                            child: Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                                color: MMColors.deepOlive),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Icon(Icons.check_circle, size: 16, color: MMColors.moss),
                                const SizedBox(width: 4),
                                Text('Uploaded', style: serif(13)),
                              ]),
                              Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: serif(14, weight: FontWeight.w400)),
                              Text(_prettySize(doc.bytes), style: serif(12, weight: FontWeight.w400)),
                            ]),
                          ),
                          IconButton(
                            tooltip: 'Replace',
                            icon: const Icon(Icons.swap_horiz, color: MMColors.deepOlive),
                            onPressed: () => _upload(type),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline, color: MMColors.deepOlive),
                            onPressed: () => _remove(type),
                          ),
                        ]),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _docs.containsKey('id_proof') && _docs.containsKey('business_proof');
    return OliveScaffold(
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(60),
              child: Center(child: CircularProgressIndicator(color: MMColors.cream)))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const StepDots(current: 2, total: 3),
              const SizedBox(height: 16),
              Center(child: Text('Upload Documents', style: serif(24, color: MMColors.cream))),
              const SizedBox(height: 8),
              Center(
                child: Text('PDF, JPG, PNG or WebP · up to 5 MB each',
                    style: serif(13, weight: FontWeight.w400, color: MMColors.cream)),
              ),
              const SizedBox(height: 20),
              Text('Identity Type:', style: serif(16, weight: FontWeight.w400, color: MMColors.cream)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _identityType,
                items: _identityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) { if (v != null) _changeIdentityType(v); },
              ),
              const SizedBox(height: 18),
              _tile(
                type: 'id_proof',
                title: '$_identityType / ID Proof',
                hint: 'A clear photo or scan of your $_identityType',
                mandatory: true,
                icon: Icons.badge_outlined,
              ),
              _tile(
                type: 'business_proof',
                title: 'Business Proof',
                hint: 'Shop licence, FSSAI, GST certificate or any proof you run this business',
                mandatory: true,
                icon: Icons.description_outlined,
              ),
              _tile(
                type: 'address_proof',
                title: 'Address Proof',
                hint: 'Electricity bill, rent agreement… (helps us verify faster)',
                mandatory: false,
                icon: Icons.home_work_outlined,
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lock_outline, size: 16, color: MMColors.cream),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your documents are stored privately and are only seen by our verification team. They are never shown to customers.',
                    style: serif(12, weight: FontWeight.w400, color: MMColors.cream),
                  ),
                ),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.amberAccent)),
              ],
              const SizedBox(height: 20),
              CreamButton(
                label: 'Next',
                onTap: (!ready || _busy.isNotEmpty) ? null : () {
                  final data = Map<String, dynamic>.from(ref.read(sellerOnboardingProvider));
                  data['identityType'] = _identityType;
                  data['idName'] = _docs['id_proof']?.name;
                  data['proofName'] = _docs['business_proof']?.name;
                  data['addressName'] = _docs['address_proof']?.name;
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
      // The files were uploaded in the previous step; this only submits the application for review.
      await ApiClient.dio.post('/businesses/${data['businessId']}/verification-documents', data: {});
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
        const StepDots(current: 3, total: 3),
        const SizedBox(height: 16),
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
            _row('ID proof', data['idName']?.toString()),
            _row('Business proof', data['proofName']?.toString()),
            if (data['addressName'] != null) _row('Address proof', data['addressName']?.toString()),
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
