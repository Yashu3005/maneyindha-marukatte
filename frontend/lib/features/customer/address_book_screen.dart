import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class AddressBookScreen extends ConsumerWidget {
  const AddressBookScreen({super.key});

  void _showAddEditDialog(BuildContext context, WidgetRef ref, [Map<String, dynamic>? existing]) {
    final isEdit = existing != null;
    final addressId = existing?['_id']?.toString();
    final labelCtrl = TextEditingController(text: existing?['label']?.toString() ?? 'Home');
    final line1Ctrl = TextEditingController(text: existing?['line1']?.toString() ?? '');
    final cityCtrl = TextEditingController(text: existing?['city']?.toString() ?? 'Bengaluru');
    final stateCtrl = TextEditingController(text: existing?['state']?.toString() ?? 'Karnataka');
    final pincodeCtrl = TextEditingController(text: existing?['pincode']?.toString() ?? '');
    bool isDefault = existing?['isDefault'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: MMColors.warmIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isEdit ? 'Edit Address' : 'Add New Address',
              style: serif(18, color: MMColors.primaryGreen)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: ['Home', 'Hostel', 'Office', 'Other'].contains(labelCtrl.text)
                      ? labelCtrl.text
                      : 'Home',
                  decoration: const InputDecoration(labelText: 'Address Label'),
                  items: ['Home', 'Hostel', 'Office', 'Other']
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => labelCtrl.text = v ?? 'Home',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: line1Ctrl,
                  decoration: const InputDecoration(labelText: 'Door No, Street & Area *'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City *'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: pincodeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: 'Pincode (6 digits) *', counterText: ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stateCtrl,
                  decoration: const InputDecoration(labelText: 'State *'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set as Default Address', style: TextStyle(fontSize: 14)),
                  value: isDefault,
                  onChanged: (v) => setDialogState(() => isDefault = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: MMColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MMColors.primaryGreen),
              onPressed: () async {
                if (line1Ctrl.text.trim().isEmpty ||
                    cityCtrl.text.trim().isEmpty ||
                    pincodeCtrl.text.trim().length != 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter valid address details and 6-digit pincode')),
                  );
                  return;
                }

                try {
                  final data = {
                    'label': labelCtrl.text.trim(),
                    'line1': line1Ctrl.text.trim(),
                    'city': cityCtrl.text.trim(),
                    'state': stateCtrl.text.trim(),
                    'pincode': pincodeCtrl.text.trim(),
                    'isDefault': isDefault,
                  };

                  if (isEdit && addressId != null) {
                    await ApiClient.dio.patch('/users/me/addresses/$addressId', data: data);
                  } else {
                    await ApiClient.dio.post('/users/me/addresses', data: data);
                  }

                  ref.invalidate(addressesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isEdit ? 'Address Updated Successfully' : 'Address Added Successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Address'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String addressId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MMColors.warmIvory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Address?'),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MMColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              try {
                await ApiClient.dio.delete('/users/me/addresses/$addressId');
                ref.invalidate(addressesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressesProvider);

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MMColors.primaryGreen),
          onPressed: () => context.pop(),
        ),
        title: Text('Address Book', style: serif(20, color: MMColors.primaryGreen)),
        elevation: 0,
      ),
      body: addressesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Could not load addresses.',
          onRetry: () => ref.invalidate(addressesProvider),
        ),
        data: (addresses) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: MMColors.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('+ Add New Address', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => _showAddEditDialog(context, ref),
                ),
              ),
              const SizedBox(height: 20),
              if (addresses.isEmpty) ...[
                const SizedBox(height: 40),
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 64, color: MMColors.secondaryGreen),
                      const SizedBox(height: 12),
                      Text('No Saved Addresses', style: serif(18, color: MMColors.primaryGreen)),
                      const SizedBox(height: 6),
                      const Text('Add an address for faster checkout.',
                          style: TextStyle(color: MMColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                ),
              ] else
                ...addresses.map((a) {
                  final id = a['_id']?.toString() ?? '';
                  final isDef = a['isDefault'] == true;
                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDef ? MMColors.primaryGreen : MMColors.sage,
                        width: isDef ? 1.5 : 0.8,
                      ),
                    ),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                a['label']?.toString() ?? 'Address',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              const Spacer(),
                              if (isDef)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: MMColors.sage,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('● Default',
                                      style: TextStyle(
                                          color: MMColors.primaryGreen,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(a['line1']?.toString() ?? '',
                              style: const TextStyle(color: MMColors.textPrimary, fontSize: 14)),
                          Text(
                            '${a['city'] ?? 'Bengaluru'}, ${a['state'] ?? 'Karnataka'} ${a['pincode'] ?? ''}',
                            style: const TextStyle(color: MMColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  side: const BorderSide(color: MMColors.primaryGreen),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _showAddEditDialog(context, ref, a),
                                child: const Text('Edit', style: TextStyle(color: MMColors.primaryGreen)),
                              ),
                              const SizedBox(width: 8),
                              if (!isDef)
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () async {
                                    try {
                                      await ApiClient.dio.post('/users/me/addresses/$id/default');
                                      ref.invalidate(addressesProvider);
                                    } catch (_) {}
                                  },
                                  child: const Text('Set as Default',
                                      style: TextStyle(color: MMColors.primaryGreen)),
                                ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _confirmDelete(context, ref, id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
