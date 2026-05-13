import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../services/category_service.dart';
import '../../services/memory_repository.dart';
import '../../widgets/memory_card.dart';
import '../../widgets/memory_actions_sheet.dart';

/// Dedicated Search tab — full-text search with optional category filter.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<MemoryItem> _results = const [];
  bool _searching = false;
  String _lastQuery = '';
  String? _filterCategoryId;
  List<CategoryDef> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _ctrl.addListener(_onQueryChanged);
  }

  Future<void> _loadCategories() async {
    final list = await CategoryService.instance.loadAllBrowsable();
    if (mounted) setState(() => _categories = list);
  }

  void _onQueryChanged() {
    final q = _ctrl.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _runSearch(q);
  }

  Future<void> _runSearch(String q) async {
    final raw = await MemoryRepository.instance.search(q);
    if (!mounted || _ctrl.text.trim() != q) return;
    final filtered = _filterCategoryId == null
        ? raw
        : raw.where((m) => m.categoryId == _filterCategoryId).toList();
    setState(() {
      _results = filtered;
      _searching = false;
    });
  }

  void _setCategory(String? id) {
    setState(() => _filterCategoryId = id);
    if (_ctrl.text.trim().isNotEmpty) _runSearch(_ctrl.text.trim());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── App bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Search',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Search field
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: false,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search memories, tags, notes…',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: scheme.onSurfaceVariant),
                        suffixIcon: _ctrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _ctrl.clear();
                                  _focus.requestFocus();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Category filter chips
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final active = _filterCategoryId == null;
                          return _FilterChip(
                            label: 'All',
                            active: active,
                            onTap: () => _setCategory(null),
                          );
                        }
                        final c = _categories[i - 1];
                        final active = _filterCategoryId == c.id;
                        return _FilterChip(
                          label: c.label,
                          icon: c.icon,
                          color: c.color,
                          active: active,
                          onTap: () => _setCategory(active ? null : c.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // ── Results ──────────────────────────────────────────────────
            Expanded(child: _buildBody(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_ctrl.text.trim().isEmpty) {
      return _EmptyPrompt(
        icon: Icons.search_rounded,
        title: 'Search your memories',
        subtitle: 'Type any word, tag, or phrase.\nSearch runs entirely on-device.',
      );
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return _EmptyPrompt(
        icon: Icons.search_off_rounded,
        title: 'No results',
        subtitle: 'Nothing matched "${_ctrl.text.trim()}".',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          DesignTokens.screenPadH, 4, DesignTokens.screenPadH, 120),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => MemoryCard(
        item: _results[i],
        onLongPress: () => showMemoryActionsSheet(context, _results[i]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              Icon(icon, size: 13, color: active ? chipColor : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
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

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
