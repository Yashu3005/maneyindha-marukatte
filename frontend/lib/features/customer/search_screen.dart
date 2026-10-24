import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/repositories.dart';
import '../../shared/widgets.dart';
import '../../theme/app_theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final List<String> _recentSearches = ['Chocolate Cake', 'Handmade Bag', 'Basavanagudi Tiffins'];
  String _query = '';
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider(null));
    final businessesAsync = ref.watch(businessesProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: MMColors.warmIvory,
      appBar: AppBar(
        backgroundColor: MMColors.warmIvory,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MMColors.primaryGreen),
          onPressed: () => context.pop(),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (val) => setState(() => _query = val.trim().toLowerCase()),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty && !_recentSearches.contains(val.trim())) {
              setState(() => _recentSearches.insert(0, val.trim()));
            }
          },
          decoration: InputDecoration(
            hintText: 'Search Products, Stores or Categories...',
            hintStyle: const TextStyle(color: MMColors.textSecondary, fontSize: 14),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: MMColors.textSecondary),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: MMColors.primaryGreen),
            onPressed: () {
              // Category filter sheet
              categoriesAsync.whenData((cats) {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: MMColors.warmIvory,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Filter by Category', style: serif(18, color: MMColors.primaryGreen)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: _selectedCategory == null,
                              onSelected: (_) {
                                setState(() => _selectedCategory = null);
                                Navigator.pop(ctx);
                              },
                            ),
                            ...cats.map((c) {
                              final name = c['name']?.toString() ?? '';
                              final id = c['_id']?.toString() ?? '';
                              return ChoiceChip(
                                label: Text(name),
                                selected: _selectedCategory == id,
                                onSelected: (_) {
                                  setState(() => _selectedCategory = id);
                                  Navigator.pop(ctx);
                                },
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              });
            },
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
      ),
      body: _query.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_recentSearches.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Searches',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: MMColors.textPrimary),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _recentSearches.clear()),
                        child: const Text('Clear All',
                            style: TextStyle(color: MMColors.primaryGreen, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._recentSearches.map(
                    (s) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, color: MMColors.textSecondary, size: 20),
                      title: Text(s, style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16, color: MMColors.textSecondary),
                        onPressed: () => setState(() => _recentSearches.remove(s)),
                      ),
                      onTap: () {
                        _controller.text = s;
                        setState(() => _query = s.toLowerCase());
                      },
                    ),
                  ),
                ],
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Products results
                productsAsync.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (products) {
                    final matched = products.where((p) {
                      final name = (p['name'] ?? '').toString().toLowerCase();
                      final desc = (p['description'] ?? '').toString().toLowerCase();
                      final cat = p['category']?['_id']?.toString() ?? p['category']?.toString();
                      if (_selectedCategory != null && cat != _selectedCategory) return false;
                      return name.contains(_query) || desc.contains(_query);
                    }).toList();

                    if (matched.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Products',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: MMColors.textSecondary)),
                        const SizedBox(height: 8),
                        ...matched.map((p) {
                          final images = (p['images'] as List?) ?? [];
                          final first = images.isNotEmpty ? images.first.toString() : null;
                          return Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: MMColors.sage, width: 0.8),
                            ),
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 48, height: 48, child: NetImage(first)),
                              ),
                              title: Text(p['name']?.toString() ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(rupees(p['price']),
                                  style: const TextStyle(
                                      color: MMColors.primaryGreen, fontWeight: FontWeight.w700)),
                              trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                              onTap: () => context.push('/product/${p['_id']}'),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),

                // Stores results
                businessesAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (stores) {
                    final matched = stores.where((s) {
                      final name = (s['name'] ?? '').toString().toLowerCase();
                      final desc = (s['description'] ?? '').toString().toLowerCase();
                      return name.contains(_query) || desc.contains(_query);
                    }).toList();

                    if (matched.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stores',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: MMColors.textSecondary)),
                        const SizedBox(height: 8),
                        ...matched.map((s) => Card(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: MMColors.sage, width: 0.8),
                              ),
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: MMColors.sage,
                                  backgroundImage: s['logoUrl'] != null ? NetworkImage(s['logoUrl']) : null,
                                  child: s['logoUrl'] == null
                                      ? const Icon(Icons.storefront, color: MMColors.primaryGreen)
                                      : null,
                                ),
                                title: Row(
                                  children: [
                                    Text(s['name']?.toString() ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified, size: 14, color: MMColors.primaryGreen),
                                  ],
                                ),
                                subtitle: Text(
                                  (s['address'] as Map?)?['city']?.toString() ?? 'Bengaluru',
                                  style: const TextStyle(fontSize: 12, color: MMColors.textSecondary),
                                ),
                                trailing: const Icon(Icons.chevron_right, color: MMColors.textSecondary),
                                onTap: () => context.push('/business/${s['_id']}'),
                              ),
                            )),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}
