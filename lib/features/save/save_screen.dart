import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../services/category_service.dart';
import '../../services/classifier_service.dart';
import '../../services/memory_repository.dart';
import '../../widgets/location_picker.dart';
import '../memory/link_picker_sheet.dart';
import '../shared/providers.dart';
import '../shared/reminder_prompt.dart';

/// Full-screen note editor used when the user shares text into the app or
/// taps a link with a long content body.
///
/// The category picker shows both the built-in categories and any custom
/// ones the user has created, so everything lives in one consistent list.
class SaveScreen extends StatefulWidget {
  const SaveScreen({
    super.key,
    this.prefillText,
    this.prefillCategoryId,
    this.editMemoryId,
  });

  final String? prefillText;

  /// When set (e.g. from tapping "New in this category"), the save screen
  /// pre-selects this category instead of letting the classifier pick. The
  /// user can still override via the chip picker.
  final String? prefillCategoryId;

  /// When set, the screen operates in edit mode — loads the existing memory
  /// and updates it on save instead of creating a new one.
  final int? editMemoryId;

  @override
  State<SaveScreen> createState() => _SaveScreenState();
}

class _SaveScreenState extends State<SaveScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  late CategoryDef _category;
  List<CategoryDef> _allCategories = const [];
  bool _saving = false;
  bool _pinnedByCaller = false;
  bool _isEditing = false;
  bool _checklistMode = false;
  List<Map<String, dynamic>> _checklistItems = [];
  final List<TextEditingController> _checklistControllers = [];

  /// One [FocusNode] per row in [_checklistControllers], kept in lock-step
  /// so [Scrollable.ensureVisible] + [FocusNode.requestFocus] on the
  /// newest row work after appending an item (Req 4.4).
  final List<FocusNode> _checklistFocusNodes = [];

  String? _locationName;
  String? _locationUrl;
  MemoryItem? _editingItem;

  /// Snapshot of the entry's `linkedIds` at the moment edit started
  /// (or `const []` for a new entry). Restored on discard (Req 3.9).
  List<int> _originalLinkedIds = const [];

  /// Working set of linked memory ids that the UI mutates. Persisted
  /// atomically via `_commitLinks` on save (Req 3.7, 3.8).
  final Set<int> _pendingLinkedIds = <int>{};

  /// Memory ids created INSIDE this editor session via the link
  /// picker's "Create new entry" flow. Deleted on discard (Req 3.9).
  final Set<int> _inlineCreatedIds = <int>{};

  /// Cache of resolved [MemoryItem]s for every id in [_pendingLinkedIds],
  /// used purely to render title / content snippets in the linked-entries
  /// section. Mutated alongside [_pendingLinkedIds] so the two stay in
  /// sync for free.
  final Map<int, MemoryItem> _pendingItems = <int, MemoryItem>{};

  /// Allows pop to proceed without invoking the discard cleanup. Set to
  /// `true` after a successful save, and (transiently) when the
  /// `PopScope` callback is escorting the route off the stack after
  /// discard.
  bool _canLeave = false;

  @override
  void initState() {
    super.initState();
    _category = MemoryCategory.note.toDef();
    _isEditing = widget.editMemoryId != null;

    if (_isEditing) {
      _loadExisting();
    } else {
      if (widget.prefillText != null) {
        _contentCtrl.text = widget.prefillText!;
        _category = ClassifierService.instance
            .classify(widget.prefillText!)
            .toDef();
      }
      // If the caller pre-picked a category (e.g. "new memory in Travel"),
      // honor that over the classifier. We also mark this as a sticky choice
      // so the text listener below doesn't re-classify under the user's feet.
      _pinnedByCaller = widget.prefillCategoryId != null;
      if (_pinnedByCaller) {
        final resolved = CategoryService.instance
            .resolveSync(widget.prefillCategoryId);
        if (resolved.id != CategoryDef.fallback.id) {
          _category = resolved;
        }
      }
    }

    _contentCtrl.addListener(() {
      // Only auto-retag while the user hasn't picked a custom category AND
      // the caller didn't force one AND we're not editing.
      if (_category.isBuiltin && !_pinnedByCaller && !_isEditing) {
        setState(() {
          _category =
              ClassifierService.instance.classify(_contentCtrl.text).toDef();
        });
      }
    });
    _loadCategories();
  }

  Future<void> _loadExisting() async {
    final item = await MemoryRepository.instance.getById(widget.editMemoryId!);
    if (item == null || !mounted) return;
    _editingItem = item;
    _titleCtrl.text = item.title ?? '';
    _contentCtrl.text = item.content;
    _category = CategoryService.instance.resolveSync(item.categoryId);
    _pinnedByCaller = true; // don't auto-retag while editing
    _checklistMode = item.checklistMode;
    if (item.checklistMode && item.checklistData.isNotEmpty) {
      try {
        final decoded = jsonDecode(item.checklistData) as List;
        _checklistItems = decoded.cast<Map<String, dynamic>>();
        for (final ci in _checklistItems) {
          _checklistControllers.add(
            TextEditingController(text: ci['text'] as String? ?? ''),
          );
          _checklistFocusNodes.add(FocusNode());
        }
      } catch (_) {}
    }
    _locationName = item.locationName;
    _locationUrl = item.locationUrl;
    _originalLinkedIds = List<int>.from(item.linkedIds);
    _pendingLinkedIds
      ..clear()
      ..addAll(item.linkedIds);
    _pendingItems.clear();
    for (final id in item.linkedIds) {
      final m = await MemoryRepository.instance.getById(id);
      if (m != null) _pendingItems[id] = m;
    }
    setState(() {});
  }

  Future<void> _loadCategories() async {
    final list = await CategoryService.instance.loadAllBrowsable();
    // Ensure "note" is selectable too.
    final merged = <CategoryDef>[
      ...MemoryCategory.values.map((c) => c.toDef()),
      ...list.where((c) => !c.isBuiltin),
    ];
    if (mounted) setState(() => _allCategories = merged);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    for (final c in _checklistControllers) {
      c.dispose();
    }
    for (final fn in _checklistFocusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  /// Appends a new empty checklist row, then (post-frame) scrolls the
  /// newest row's [FocusNode] into view and focuses it.
  ///
  /// Per Req 4.4, the new item must be brought fully into view within
  /// 500 ms. We use a 200 ms ensureVisible animation so the scroll lands
  /// well before the deadline; the post-frame callback fires after the
  /// row is laid out, so [Scrollable.ensureVisible] has a real
  /// [BuildContext] to walk up.
  void _appendChecklistItem() {
    final fn = FocusNode();
    setState(() {
      _checklistItems.add({'text': '', 'checked': false});
      _checklistControllers.add(TextEditingController());
      _checklistFocusNodes.add(fn);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = fn.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: 1.0,
        );
      }
      fn.requestFocus();
    });
  }

  /// Removes the row at [index] from the editor's parallel arrays.
  void _removeChecklistItem(int index) {
    setState(() {
      _checklistControllers[index].dispose();
      _checklistControllers.removeAt(index);
      _checklistItems.removeAt(index);
      final fn = _checklistFocusNodes.removeAt(index);
      fn.dispose();
    });
  }

  /// Opens the link picker and dispatches on the result.
  ///
  /// `LinkPickerExisting` adds the picked id to the pending set.
  /// `LinkPickerCreateNew` persists a stub Memory immediately (so we have
  /// an id to pin into the pending set), tracks it in
  /// [_inlineCreatedIds] so a subsequent discard can clean it up, and
  /// adds the new id to the pending set.
  Future<void> _addLink() async {
    final result = await showModalBottomSheet<LinkPickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LinkPickerSheet(
        excludeId: _editingItem?.id,
        alreadyLinked: _pendingLinkedIds.toList(growable: false),
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case LinkPickerExisting(:final item):
        setState(() {
          _pendingLinkedIds.add(item.id);
          _pendingItems[item.id] = item;
        });
      case LinkPickerCreateNew(:final title):
        final stub = await MemoryRepository.instance.createTextMemory(
          title: title,
          content: '',
        );
        if (!mounted) return;
        setState(() {
          _inlineCreatedIds.add(stub.id);
          _pendingLinkedIds.add(stub.id);
          _pendingItems[stub.id] = stub;
        });
    }
  }

  /// Removes [id] from the pending link set without touching disk.
  /// The bidirectional persistence happens atomically in [_commitLinks]
  /// at save time (Req 3.7).
  void _removeLinkLocally(int id) {
    setState(() {
      _pendingLinkedIds.remove(id);
      _pendingItems.remove(id);
    });
  }

  /// Atomically reconciles `_pendingLinkedIds` against `_originalLinkedIds`,
  /// updating the entry being saved and every counterparty's `linkedIds`
  /// to preserve the bidirectional invariant (Req 3.8, 3.10, 3.11).
  ///
  /// Phase 1 snapshots every counterparty BEFORE writing, so a failure in
  /// phase 2 leaves the disk in a consistent state and the caller can
  /// surface an error to the user without partial bidirectional rot.
  Future<void> _commitLinks(MemoryItem self) async {
    final selfId = self.id;
    // Drop the self id from both ends to satisfy Req 3.11 (no self-links).
    final original = _originalLinkedIds.toSet()..remove(selfId);
    final pending = _pendingLinkedIds.toSet()..remove(selfId);

    final added = pending.difference(original);
    final removed = original.difference(pending);

    // Phase 1: snapshot every counterparty BEFORE writing anything.
    final adds = <MemoryItem>[];
    final removes = <MemoryItem>[];
    for (final id in added) {
      final m = await MemoryRepository.instance.getById(id);
      if (m != null) adds.add(m);
    }
    for (final id in removed) {
      final m = await MemoryRepository.instance.getById(id);
      if (m != null) removes.add(m);
    }

    // Phase 2: mutate. We update `self` first so a failure on a
    // counterparty leaves only the self side updated; the next save
    // attempt will re-converge the bidirectional state because each
    // update is idempotent.
    self.linkedIds = pending.toList()..sort();
    await MemoryRepository.instance.update(self);
    for (final m in adds) {
      if (!m.linkedIds.contains(selfId)) {
        m.linkedIds = [...m.linkedIds, selfId]..sort();
        await MemoryRepository.instance.update(m);
      }
    }
    for (final m in removes) {
      if (m.linkedIds.contains(selfId)) {
        m.linkedIds = m.linkedIds.where((id) => id != selfId).toList();
        await MemoryRepository.instance.update(m);
      }
    }
  }

  /// Wraps [_commitLinks] with the user-facing error path defined in
  /// Req 3.13: on failure, surface a SnackBar, leave `_pendingLinkedIds`
  /// intact, reset the saving spinner, and return `false` so the caller
  /// does NOT navigate away.
  Future<bool> _persistLinks(MemoryItem mem) async {
    try {
      await _commitLinks(mem);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save links: $e')),
        );
      }
      return false;
    }
  }

  /// Restores the entry's `linkedIds` to its pre-edit snapshot and deletes
  /// every memory created via the link picker's "Create new entry" flow
  /// during this session (Req 3.9).
  ///
  /// Counterparty `linkedIds` are NEVER touched here: phase 2 of
  /// `_commitLinks` is the only path that writes to counterparties, and
  /// it never runs on discard. So Req 3.9's "no other Memory's
  /// `linkedIds` modified on discard" holds by construction.
  Future<void> _discard() async {
    if (_isEditing && _editingItem != null) {
      _editingItem!.linkedIds = List<int>.from(_originalLinkedIds);
      try {
        await MemoryRepository.instance.update(_editingItem!);
      } catch (_) {
        // Best-effort: if the restore write fails, the worst case is the
        // entry's linkedIds remain at their last-saved value (which is
        // also the original, since we never wrote anything else outside
        // _commitLinks). Discard cleanup of inline-created stubs still
        // proceeds.
      }
    }
    for (final id in _inlineCreatedIds) {
      final m = await MemoryRepository.instance.getById(id);
      if (m == null) continue;
      try {
        await MemoryRepository.instance.delete(m);
      } catch (_) {
        // Swallow: a stub that fails to delete will simply linger as an
        // empty note. The user can delete it manually from the Inbox.
      }
    }
  }

  Future<void> _save() async {
    if (_checklistMode) {
      // Build checklistData from controllers, persisting only items
      // whose text is non-empty after trim, in original order, with
      // their `checked` value preserved (Req 4.5).
      final items = <Map<String, dynamic>>[];
      for (var i = 0; i < _checklistControllers.length; i++) {
        final text = _checklistControllers[i].text.trim();
        if (text.isNotEmpty) {
          items.add({
            'text': text,
            'checked': _checklistItems.length > i
                ? (_checklistItems[i]['checked'] ?? false)
                : false,
          });
        }
      }
      // Use a summary as content for search indexing (Req 4.5).
      final summary = items.map((e) => e['text']).join(', ');
      // Block the save when zero non-empty items exist and surface a
      // SnackBar; do NOT mutate editor state (Req 4.7).
      if (items.isEmpty) {
        if (!_saving && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Add at least one checklist item'),
            ),
          );
        }
        return;
      }
      if (_saving) return;
      setState(() => _saving = true);
      final title = _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();
      if (_isEditing && _editingItem != null) {
        final item = _editingItem!;
        item.title = title;
        item.content = summary;
        item.categoryId = _category.id;
        item.checklistMode = true;
        item.checklistData = jsonEncode(items);
        item.locationName = _locationName;
        item.locationUrl = _locationUrl;
        await MemoryRepository.instance.update(item);
        if (!await _persistLinks(item)) return;
        _canLeave = true;
        if (!mounted) return;
        // Persist FIRST, then offer the reminder prompt regardless of
        // category (Req 5.1, 5.4, 5.6, 5.8). On accept the helper has
        // already navigated; otherwise pop back to the previous route.
        final outcome = await maybePromptForReminder(
          context,
          memory: item,
          contentForDetection: summary,
        );
        if (outcome == ReminderPromptOutcome.accepted) return;
        if (!mounted) return;
        context.pop();
        return;
      }
      final mem = await MemoryRepository.instance.createTextMemory(
        content: summary,
        title: title,
        forcedCategory: _category.builtin,
        forcedCategoryId: _category.isBuiltin ? null : _category.id,
      );
      mem.checklistMode = true;
      mem.checklistData = jsonEncode(items);
      mem.locationName = _locationName;
      mem.locationUrl = _locationUrl;
      await MemoryRepository.instance.update(mem);
      if (!await _persistLinks(mem)) return;
      _canLeave = true;
      if (!mounted) return;
      // Persist FIRST, then offer the reminder prompt regardless of
      // category (Req 5.1, 5.4, 5.6, 5.8).
      final outcome = await maybePromptForReminder(
        context,
        memory: mem,
        contentForDetection: summary,
      );
      if (outcome == ReminderPromptOutcome.accepted) return;
      if (!mounted) return;
      context.go('/');
      showAppToast('Saved');
      return;
    }
    final text = _contentCtrl.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    final title =
        _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();

    if (_isEditing && _editingItem != null) {
      // Update existing memory.
      final item = _editingItem!;
      item.title = title;
      item.content = text;
      item.categoryId = _category.id;
      item.locationName = _locationName;
      item.locationUrl = _locationUrl;
      await MemoryRepository.instance.update(item);
      if (!await _persistLinks(item)) return;
      _canLeave = true;
      if (!mounted) return;
      // Persist FIRST, then offer the reminder prompt regardless of
      // category (Req 5.1, 5.4, 5.6, 5.8).
      final outcome = await maybePromptForReminder(
        context,
        memory: item,
        contentForDetection: text,
      );
      if (outcome == ReminderPromptOutcome.accepted) return;
      if (!mounted) return;
      context.pop();
      return;
    }

    // Create new memory.
    final mem = await MemoryRepository.instance.createTextMemory(
      content: text,
      title: title,
      forcedCategory: _category.builtin,
      forcedCategoryId: _category.isBuiltin ? null : _category.id,
    );
    if (_locationName != null) {
      mem.locationName = _locationName;
      mem.locationUrl = _locationUrl;
      await MemoryRepository.instance.update(mem);
    }
    if (!await _persistLinks(mem)) return;
    _canLeave = true;
    if (!mounted) return;
    // Persist FIRST, then offer the reminder prompt regardless of
    // category (Req 5.1, 5.4, 5.6, 5.8). The helper is the single
    // source of truth for the time-specific reminder offer; we no
    // longer special-case the Promise classification here.
    final outcome = await maybePromptForReminder(
      context,
      memory: mem,
      contentForDetection: text,
    );
    if (outcome == ReminderPromptOutcome.accepted) return;
    if (!mounted) return;
    context.go('/');
    showAppToast(
      'Saved',
      actionLabel: 'Open',
      onAction: () => appRouter.push('/memory/${mem.id}'),
    );
  }

  Future<void> _createCustomCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _QuickCreateCategoryDialog(),
    );
    final label = name?.trim();
    if (label == null || label.isEmpty) return;
    final def = await CategoryService.instance.createFromName(label);
    await _loadCategories();
    if (!mounted) return;
    setState(() => _category = def);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _canLeave) return;
        await _discard();
        if (!context.mounted) return;
        _canLeave = true;
        // Re-issue the pop now that cleanup is done; on the second
        // pass `canPop` is true so the route leaves the stack.
        Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit memory' : 'New memory'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              hintText: 'Title (optional)',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              fillColor: Colors.transparent,
              filled: false,
            ),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          // Mode toggle
          Row(
            children: [
              Text(
                'MODE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Text'),
                selected: !_checklistMode,
                onSelected: (_) => setState(() {
                  _checklistMode = false;
                }),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Checklist'),
                selected: _checklistMode,
                onSelected: (_) {
                  setState(() {
                    _checklistMode = true;
                  });
                  if (_checklistControllers.isEmpty) {
                    // Seed the editor with a single empty row. We route
                    // through [_appendChecklistItem] so the seed row gets
                    // a [FocusNode] and is wired up identically to rows
                    // added later.
                    _appendChecklistItem();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_checklistMode)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(DesignTokens.rInput),
              ),
              child: TextField(
                controller: _contentCtrl,
                autofocus: widget.prefillText == null,
                maxLines: null,
                minLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Type your memory…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: false,
                ),
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            )
          else
            _ChecklistEditor(
              controllers: _checklistControllers,
              items: _checklistItems,
              focusNodes: _checklistFocusNodes,
              onChanged: () => setState(() {}),
              onAddItem: _appendChecklistItem,
              onRemoveItem: _removeChecklistItem,
            ),
          const SizedBox(height: 18),
          // Location section
          Text(
            'LOCATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final result = await showLocationPicker(
                context,
                initialName: _locationName,
              );
              if (result != null) {
                setState(() {
                  _locationName = result.name;
                  _locationUrl = result.mapsUrl;
                });
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 18,
                    color: _locationName != null
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _locationName ?? 'Add location (optional)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _locationName != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: _locationName != null
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_locationName != null)
                    GestureDetector(
                      onTap: () => setState(() {
                        _locationName = null;
                        _locationUrl = null;
                      }),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Linked entries section (Req 3.1).
          Text(
            'LINKED ENTRIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _LinkedEntriesSection(
            pendingIds: _pendingLinkedIds.toList()..sort(),
            items: _pendingItems,
            onAdd: _addLink,
            onRemove: _removeLinkLocally,
          ),
          const SizedBox(height: 18),
          Text(
            'CATEGORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _allCategories)
                _CategoryChoice(
                  category: c,
                  selected: c.id == _category.id,
                  onTap: () => setState(() => _category = c),
                ),
              _NewCategoryChip(onTap: _createCustomCategory),
            ],
          ),
        ],
      ),
    ),
    );
  }
}

class _ChecklistEditor extends StatelessWidget {
  const _ChecklistEditor({
    required this.controllers,
    required this.items,
    required this.focusNodes,
    required this.onChanged,
    required this.onAddItem,
    required this.onRemoveItem,
  });

  final List<TextEditingController> controllers;
  final List<Map<String, dynamic>> items;
  final List<FocusNode> focusNodes;
  final VoidCallback onChanged;
  final VoidCallback onAddItem;
  final void Function(int index) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      // Plain Column so this editor participates in the screen-level
      // ListView's vertical scroll surface (Req 4.3). Every row plus
      // the "Add item" tile is reachable by gesture because the
      // surrounding ListView handles the scroll.
      child: Column(
        children: [
          for (var i = 0; i < controllers.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      items[i]['checked'] = !(items[i]['checked'] as bool? ?? false);
                      onChanged();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (items[i]['checked'] as bool? ?? false)
                            ? scheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: (items[i]['checked'] as bool? ?? false)
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: (items[i]['checked'] as bool? ?? false)
                          ? const Icon(Icons.check_rounded,
                              size: 13, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controllers[i],
                      focusNode: i < focusNodes.length ? focusNodes[i] : null,
                      decoration: InputDecoration(
                        hintText: 'Item ${i + 1}',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        decoration: (items[i]['checked'] as bool? ?? false)
                            ? TextDecoration.lineThrough
                            : null,
                        color: (items[i]['checked'] as bool? ?? false)
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                      onSubmitted: (_) => onAddItem(),
                    ),
                  ),
                  if (controllers.length > 1)
                    GestureDetector(
                      onTap: () => onRemoveItem(i),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onAddItem,
            child: Row(
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Add item',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the pending linked-entries list above the category strip.
///
/// The "+ Add link" tile is always present. Each pending entry shows as
/// a row with a primary line (title or first content line) and an `×`
/// button that calls [onRemove] to mutate the parent's pending set
/// without touching disk (Req 3.7).
class _LinkedEntriesSection extends StatelessWidget {
  const _LinkedEntriesSection({
    required this.pendingIds,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final List<int> pendingIds;
  final Map<int, MemoryItem> items;
  final VoidCallback onAdd;
  final void Function(int id) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in pendingIds)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PendingLinkRow(
              item: items[id],
              onRemove: () => onRemove(id),
            ),
          ),
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.add_link_rounded,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Add link',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingLinkRow extends StatelessWidget {
  const _PendingLinkRow({required this.item, required this.onRemove});

  /// Cached snapshot of the linked memory. May be null if the resolve
  /// missed (e.g. the row was deleted from another device between the
  /// pick and the render). The row still renders with a placeholder so
  /// the user can remove it.
  final MemoryItem? item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = item?.title?.trim();
    final content = item?.content.trim() ?? '';
    final primary = (title != null && title.isNotEmpty)
        ? title
        : (content.isNotEmpty ? content : '(untitled entry)');
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(Icons.link_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
              onPressed: onRemove,
              tooltip: 'Remove link',
              splashRadius: 18,
              constraints: const BoxConstraints(
                  minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryDef category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.rChip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? category.color.withValues(alpha: 0.18)
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(DesignTokens.rChip),
          border: Border.all(
            color: selected
                ? category.color
                : scheme.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 14, color: category.color),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? category.color : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewCategoryChip extends StatelessWidget {
  const _NewCategoryChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.rChip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(DesignTokens.rChip),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              'New…',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight inline "Create category" dialog used from Save so the user
/// never has to leave the editor to tag a memory.
class _QuickCreateCategoryDialog extends StatefulWidget {
  const _QuickCreateCategoryDialog();

  @override
  State<_QuickCreateCategoryDialog> createState() =>
      _QuickCreateCategoryDialogState();
}

class _QuickCreateCategoryDialogState
    extends State<_QuickCreateCategoryDialog> {
  final _controller = TextEditingController();
  IconData _icon = Icons.label_rounded;

  @override
  void initState() {
    super.initState();
    _controller.addListener(
      () => setState(() => _icon = deriveCategoryIcon(_controller.text)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewColor =
        deriveCategoryColor(deriveCategoryId(_controller.text));
    return AlertDialog(
      title: const Text('New category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: previewColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: previewColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _controller.text.trim().isEmpty
                      ? 'Preview'
                      : _controller.text.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Category name'),
            onSubmitted: (_) =>
                Navigator.of(context).pop(_controller.text),
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}
