import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/memory_item.dart';
import '../../services/memory_repository.dart';

/// Result returned by [LinkPickerSheet] when the user picks an existing
/// entry, creates a new one, or dismisses (returns `null`).
///
/// Sealed so callers must handle both variants exhaustively.
sealed class LinkPickerResult {
  const LinkPickerResult();
}

/// User picked an existing memory.
class LinkPickerExisting extends LinkPickerResult {
  const LinkPickerExisting(this.item);
  final MemoryItem item;
}

/// User asked to create a new memory with the given trimmed [title].
///
/// `title` is guaranteed to be 1..200 characters, non-whitespace,
/// trimmed. Caller is responsible for actually persisting the new
/// memory.
class LinkPickerCreateNew extends LinkPickerResult {
  const LinkPickerCreateNew(this.title);
  final String title;
}

/// Bottom sheet for picking an entry to link to.
///
/// Behavior matrix:
///  * Empty trimmed query → most-recently-updated memories, paged in
///    chunks of 50, infinite-scroll downwards.
///  * Non-empty trimmed query → 200ms debounce, then
///    [MemoryRepository.search]. Excludes [excludeId] (the current
///    entry, if persisted) and any id in [alreadyLinked].
///  * When the trimmed query is 1..200 chars, non-whitespace, AND the
///    filtered result list is empty, a leading "Create '<title>'" row
///    is rendered.
///
/// Returns one of:
///  * `LinkPickerExisting(item)` when the user taps an existing row.
///  * `LinkPickerCreateNew(title)` when the user taps the create row.
///  * `null` when the user dismisses without picking.
class LinkPickerSheet extends StatefulWidget {
  const LinkPickerSheet({
    super.key,
    required this.excludeId,
    required this.alreadyLinked,
  });

  /// Id of the entry currently being edited. Filtered from results so
  /// the user cannot self-link. `null` for new entries that have not
  /// been persisted yet (no id to exclude).
  final int? excludeId;

  /// Memory ids already in the pending link set; filtered from results
  /// so the user cannot pick a duplicate.
  final List<int> alreadyLinked;

  @override
  State<LinkPickerSheet> createState() => _LinkPickerSheetState();
}

class _LinkPickerSheetState extends State<LinkPickerSheet> {
  static const _pageSize = 50;
  static const _maxTitleLen = 200;
  static const _debounce = Duration(milliseconds: 200);

  final _ctrl = TextEditingController();

  /// Current rendered list (recents view OR search results).
  List<MemoryItem> _items = const [];

  /// True while a fetch is in flight (initial load or debounce-fired
  /// search).
  bool _loading = false;

  /// True when the recents view has loaded the last page; suppresses
  /// further infinite-scroll fetches.
  bool _recentsExhausted = false;

  /// Most recent debounce timer; cancelled on every keystroke so only
  /// the last keystroke triggers a search.
  Timer? _debounceTimer;

  /// Token of the in-flight search, used to drop stale results when
  /// the user types faster than the search resolves.
  int _searchSeq = 0;

  /// Trimmed text currently displayed in [_items]. Used to decide
  /// whether the "Create '<title>'" row is renderable.
  String _appliedQuery = '';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    _loadRecents(reset: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Filtering helpers
  // ---------------------------------------------------------------------------

  bool _shouldExclude(MemoryItem m) {
    if (widget.excludeId != null && m.id == widget.excludeId) return true;
    if (widget.alreadyLinked.contains(m.id)) return true;
    return false;
  }

  // ---------------------------------------------------------------------------
  // Text change → debounced search
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    final q = _ctrl.text.trim();
    _debounceTimer?.cancel();

    if (q.isEmpty) {
      // Cancel any in-flight search by bumping the seq.
      _searchSeq++;
      // Switch back to recents view.
      _loadRecents(reset: true);
      return;
    }

    // Schedule a debounced search; the empty-query branch above handles
    // the no-search-needed case.
    _debounceTimer = Timer(_debounce, () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    final seq = ++_searchSeq;
    setState(() {
      _loading = true;
      _recentsExhausted = true; // not relevant in search view
    });
    final raw = await MemoryRepository.instance.search(q);
    if (!mounted || seq != _searchSeq) return;
    // Re-check: the user may have typed since this fetch started.
    if (_ctrl.text.trim() != q) return;
    final filtered = raw.where((m) => !_shouldExclude(m)).toList(
          growable: false,
        );
    setState(() {
      _items = filtered;
      _appliedQuery = q;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Recents view (empty query) — paged in chunks of 50
  // ---------------------------------------------------------------------------

  Future<void> _loadRecents({required bool reset}) async {
    if (!mounted) return;
    final seq = ++_searchSeq;
    final offset = reset ? 0 : _items.length;
    setState(() {
      _loading = true;
      if (reset) {
        _items = const [];
        _recentsExhausted = false;
        _appliedQuery = '';
      }
    });
    final page = await MemoryRepository.instance.fetchRecent(
      limit: _pageSize,
      offset: offset,
    );
    if (!mounted || seq != _searchSeq) return;
    final visible = page.where((m) => !_shouldExclude(m)).toList();
    setState(() {
      _items = reset ? visible : [..._items, ...visible];
      _loading = false;
      // If the underlying page came back smaller than _pageSize, there
      // are no more rows on disk.
      _recentsExhausted = page.length < _pageSize;
    });
  }

  void _onScroll(ScrollNotification n) {
    if (_loading || _recentsExhausted) return;
    if (_ctrl.text.trim().isNotEmpty) return; // only paginate recents
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
      _loadRecents(reset: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  bool get _showCreateRow {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return false;
    if (q.length > _maxTitleLen) return false;
    if (_loading) return false;
    if (_items.isNotEmpty) return false;
    // _appliedQuery == q means the current results reflect this query;
    // otherwise the user is mid-debounce and we should not show the
    // create row yet (avoids flashing it during typing).
    return _appliedQuery == q;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, sheetController) => Column(
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.add_link_rounded,
                        color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Link to entry',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search entries to link…',
                      prefixIcon: Icon(Icons.search_rounded,
                          color: scheme.onSurfaceVariant, size: 20),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(scheme, sheetController)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, ScrollController sheetController) {
    final showCreate = _showCreateRow;

    if (_loading && _items.isEmpty && !showCreate) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_items.isEmpty && !showCreate) {
      final q = _ctrl.text.trim();
      final emptyText = q.isEmpty ? 'No memories yet' : 'No results';
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        ),
      );
    }

    // Item count: optional create-new row + items + optional trailing
    // loading spinner for paginated recents.
    final hasTrailingLoader = _loading && _items.isNotEmpty;
    final createOffset = showCreate ? 1 : 0;
    final loaderOffset = hasTrailingLoader ? 1 : 0;
    final totalCount = createOffset + _items.length + loaderOffset;

    // The DraggableScrollableSheet supplies a controller that must
    // drive the inner scrollable so the sheet drag-to-expand works.
    // Pagination is wired via a NotificationListener so it can
    // observe scroll position without competing for the controller.
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _onScroll(n);
        return false;
      },
      child: ListView.separated(
        controller: sheetController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: totalCount,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (showCreate && i == 0) {
            return _CreateNewRow(
              title: _ctrl.text.trim(),
              onTap: () {
                Navigator.of(context).pop(
                  LinkPickerCreateNew(_ctrl.text.trim()),
                );
              },
            );
          }
          final itemIndex = i - createOffset;
          if (itemIndex >= _items.length) {
            // trailing loader
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final m = _items[itemIndex];
          return _ExistingRow(
            item: m,
            onTap: () {
              Navigator.of(context).pop(LinkPickerExisting(m));
            },
          );
        },
      ),
    );
  }
}

/// Tappable row that renders an existing [MemoryItem] preview.
class _ExistingRow extends StatelessWidget {
  const _ExistingRow({required this.item, required this.onTap});
  final MemoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.title != null && item.title!.isNotEmpty)
                Text(
                  item.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                item.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable "Create '<title>'" row shown when search has no hits.
class _CreateNewRow extends StatelessWidget {
  const _CreateNewRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: 'Create '),
                      TextSpan(
                        text: "'$title'",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
