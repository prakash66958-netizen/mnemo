import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../services/category_service.dart';
import '../../services/memory_repository.dart';
import '../../widgets/memory_card.dart';
import '../../widgets/memory_actions_sheet.dart';
import '../../widgets/section_label.dart';
import '../shared/providers.dart';

/// Browse tab — category grid + integrated search.
class CategoriesTab extends ConsumerStatefulWidget {
  const CategoriesTab({super.key});

  @override
  ConsumerState<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<CategoriesTab> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  List<MemoryItem> _searchResults = const [];
  bool _searching = false;
  String _lastQuery = '';
  String? _filterCategoryId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _isSearching => _searchCtrl.text.trim().isNotEmpty;

  void _onQueryChanged() {
    final q = _searchCtrl.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    setState(() {});
    if (q.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _runSearch(q);
  }

  Future<void> _runSearch(String q) async {
    final raw = await MemoryRepository.instance.search(q);
    if (!mounted || _searchCtrl.text.trim() != q) return;
    final filtered = _filterCategoryId == null
        ? raw
        : raw.where((m) => m.categoryId == _filterCategoryId).toList();
    setState(() {
      _searchResults = filtered;
      _searching = false;
    });
  }

  void _setFilter(String? id) {
    setState(() => _filterCategoryId = id);
    if (_isSearching) _runSearch(_searchCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final countsAsync = ref.watch(categoryCountsProvider);
    final categoriesAsync = ref.watch(categoryListProvider);
    final inboxAsync = ref.watch(inboxStreamProvider);

    final categories = categoriesAsync.asData?.value ?? const <CategoryDef>[];

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── App bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Browse',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (!_isSearching)
                              Text(
                                '${inboxAsync.maybeWhen(data: (v) => v.length, orElse: () => 0)} memories · ${categories.length} categories',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!_isSearching)
                        InkWell(
                          onTap: () => _promptForNewCategory(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            child: Icon(Icons.add_rounded,
                                size: 22, color: scheme.onSurface),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search memories…',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: scheme.onSurfaceVariant, size: 20),
                        suffixIcon: _isSearching
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _searchFocus.unfocus();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                      ),
                    ),
                  ),
                  // Category filter chips — only shown while searching
                  if (_isSearching) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return _SearchChip(
                              label: 'All',
                              active: _filterCategoryId == null,
                              onTap: () => _setFilter(null),
                            );
                          }
                          final c = categories[i - 1];
                          final active = _filterCategoryId == c.id;
                          return _SearchChip(
                            label: c.label,
                            icon: c.icon,
                            color: c.color,
                            active: active,
                            onTap: () => _setFilter(active ? null : c.id),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── Body ─────────────────────────────────────────────────────
            Expanded(
              child: _isSearching
                  ? _buildSearchResults(scheme)
                  : _buildCategoryGrid(countsAsync, categoriesAsync),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme scheme) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 52,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              const Text(
                'No results',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Nothing matched "${_searchCtrl.text.trim()}".',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => MemoryCard(
        item: _searchResults[i],
        onLongPress: () =>
            showMemoryActionsSheet(context, _searchResults[i]),
      ),
    );
  }

  Widget _buildCategoryGrid(
    AsyncValue<Map<String, int>> countsAsync,
    AsyncValue<List<CategoryDef>> categoriesAsync,
  ) {
    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed: $e')),
      data: (categories) {
        final counts =
            countsAsync.asData?.value ?? const <String, int>{};
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            const SectionLabel(label: 'Categories'),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
              ),
              itemCount: categories.length + 1,
              itemBuilder: (_, i) {
                if (i == categories.length) {
                  return _AddCategoryTile(
                    onTap: () => _promptForNewCategory(context),
                  );
                }
                final c = categories[i];
                return _CategoryTile(
                  def: c,
                  count: counts[c.id] ?? 0,
                  onLongPress: c.isBuiltin
                      ? null
                      : () => _showCustomCategoryMenu(context, c),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _promptForNewCategory(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );
    final label = name?.trim();
    if (label == null || label.isEmpty) return;
    try {
      final def =
          await ref.read(categoryServiceProvider).createFromName(label);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "${def.label}"')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create category: $e')),
        );
      }
    }
  }

  void _showCustomCategoryMenu(BuildContext context, CategoryDef def) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(def.icon, color: def.color),
              title: Text(def.label),
              subtitle: const Text('Custom category'),
            ),
            const Divider(height: 1),
            ListTile(
              leading:
                  const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(context).pop();
                final newName = await showDialog<String>(
                  context: context,
                  builder: (_) => _NewCategoryDialog(initial: def.label),
                );
                if (newName != null && newName.trim().isNotEmpty) {
                  await ref
                      .read(categoryServiceProvider)
                      .rename(def, newName.trim());
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete category',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              subtitle: const Text(
                  'Memories inside stay, but will show as generic until re-tagged.'),
              onTap: () async {
                Navigator.of(context).pop();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Delete "${def.label}"?'),
                    content: const Text(
                        'This removes the category but not the memories inside it.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel')),
                      FilledButton.tonal(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(categoryServiceProvider).delete(def);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Small filter chip used in the search results view.
class _SearchChip extends StatelessWidget {
  const _SearchChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chipColor = color ?? scheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? chipColor.withValues(alpha: 0.18)
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? chipColor.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12,
                  color: active ? chipColor : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? chipColor : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.def,
    required this.count,
    this.onLongPress,
  });

  final CategoryDef def;
  final int count;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final tintAlpha = brightness == Brightness.light ? 0.10 : 0.16;

    return Material(
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(DesignTokens.rCard),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CategoryDetailScreen(category: def),
            ),
          );
        },
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: def.color.withValues(alpha: tintAlpha),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: def.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(def.icon, color: Colors.white, size: 22),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        def.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count == 1 ? '1 item' : '$count items',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCategoryTile extends StatelessWidget {
  const _AddCategoryTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(DesignTokens.rCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: _DottedBorderPainter(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            radius: DesignTokens.rCard,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'New category',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Icon auto-picked',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  _DottedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path()..addRRect(rect);
    const dash = 5.0;
    const gap = 4.0;
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      var distance = 0.0;
      while (distance < m.length) {
        final segment = m.extractPath(distance, distance + dash);
        canvas.drawPath(segment, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog({this.initial});
  final String? initial;

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  late final TextEditingController _controller;
  late IconData _previewIcon;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
    _previewIcon = deriveCategoryIcon(_controller.text);
    _controller.addListener(() {
      setState(() => _previewIcon = deriveCategoryIcon(_controller.text));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewColor =
        deriveCategoryColor(deriveCategoryId(_controller.text));
    return AlertDialog(
      title: Text(
          widget.initial == null ? 'New category' : 'Rename category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: previewColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_previewIcon, color: previewColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _controller.text.trim().isEmpty
                      ? 'Preview'
                      : _controller.text.trim(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Travel, Gym, Recipes',
            ),
            onSubmitted: (_) => Navigator.of(context).pop(_controller.text),
          ),
          const SizedBox(height: 8),
          Text(
            'Mnemo picks a theme-matching icon based on the name.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.initial == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Secondary screen showing all items for a single category.
class CategoryDetailScreen extends ConsumerWidget {
  const CategoryDetailScreen({super.key, required this.category});
  final CategoryDef category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoryMemoriesProvider(category.id));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: category.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(category.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(category.label),
          ],
        ),
      ),
      // Tapping this FAB jumps straight into the save editor with the
      // current category pre-selected, so "I want to jot something in
      // Travel" becomes one tap instead of three.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/save', extra: {
          'categoryId': category.id,
        }),
        backgroundColor: category.color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('New in ${category.label}'),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon,
                        size: 48,
                        color: category.color.withValues(alpha: 0.8)),
                    const SizedBox(height: 14),
                    Text(
                      'Nothing in ${category.label} yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "New in ${category.label}" below to add your '
                      'first one, or let Mnemo auto-tag items here as you '
                      'save.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => MemoryCard(
              item: items[i],
              onLongPress: () => showMemoryActionsSheet(context, items[i]),
            ),
          );
        },
      ),
    );
  }
}
