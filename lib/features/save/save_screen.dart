import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../services/category_service.dart';
import '../../services/classifier_service.dart';
import '../../services/memory_repository.dart';
import '../../services/promise_detector.dart';
import '../shared/providers.dart';

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
  MemoryItem? _editingItem;

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
    super.dispose();
  }

  Future<void> _save() async {
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
      await MemoryRepository.instance.update(item);
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
    if (!mounted) return;
    // Only auto-redirect to reminder creation if the CLASSIFIER detected a
    // promise (not just because the user manually picked the Promise/Reminder
    // category). This prevents the confusing "I just wanted to save a note in
    // Promise category" → forced into reminder flow.
    final detection = PromiseDetector.instance.detect(text);
    if (detection.hasPromise && !_pinnedByCaller) {
      context.go('/reminder/new', extra: {
        'memoryId': mem.id,
        'text': detection.action ?? text,
        'time': detection.suggestedTime,
      });
    } else {
      context.go('/');
      showAppToast(
        'Saved',
        actionLabel: 'Open',
        onAction: () => appRouter.push('/memory/${mem.id}'),
      );
    }
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
    return Scaffold(
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
