import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../services/category_service.dart';
import '../../services/classifier_service.dart';
import '../../services/memory_repository.dart';
import '../../services/promise_detector.dart';
import '../shared/providers.dart';
import '../shared/reminder_prompt.dart';

/// Quick-capture bottom sheet. Matches screen #2 of the HTML mockup:
/// a rounded sheet with a grip, title + close, large textbox, "Suggested"
/// chips that react to what the user types, source tiles, and a Save CTA.
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key});

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _ctrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<CategoryDef> _allCategories = const [];
  CategoryDef _selected = MemoryCategory.note.toDef();
  bool _userOverrodeCategory = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _loadCategories();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    _titleCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final list = await CategoryService.instance.loadAllBrowsable();
    if (!mounted) return;
    setState(() {
      _allCategories = [
        ...MemoryCategory.values.map((c) => c.toDef()),
        ...list.where((c) => !c.isBuiltin),
      ];
    });
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      // Only auto-retag while the user hasn't explicitly picked a category.
      if (_userOverrodeCategory) return;
      setState(() => _selected = _autoCategory(_ctrl.text));
    });
  }

  /// Deterministic auto-pick: promise detector wins first, then classifier,
  /// fall back to Note. Custom categories are never auto-picked — the
  /// classifier only knows about built-ins.
  CategoryDef _autoCategory(String text) {
    final t = text.trim();
    if (t.isEmpty) return MemoryCategory.note.toDef();
    final hasPromise = PromiseDetector.instance.detect(t).hasPromise;
    if (hasPromise) return MemoryCategory.promise.toDef();
    return ClassifierService.instance.classify(t).toDef();
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    final title = _titleCtrl.text.trim();
    // Allow saving with just a title OR just content (or both).
    if (text.isEmpty && title.isEmpty) return;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final category = _selected;
      final mem = await MemoryRepository.instance.createTextMemory(
        content: text.isNotEmpty ? text : '',
        title: title.isNotEmpty ? title : null,
        forcedCategory: category.builtin,
        forcedCategoryId: category.isBuiltin ? null : category.id,
      );
      if (!mounted) return;
      // Persist FIRST (Req 5.8), then offer the reminder prompt regardless
      // of category. The shared helper is the single source of truth for
      // when a reminder follow-up is offered.
      final outcome = await maybePromptForReminder(
        context,
        memory: mem,
        contentForDetection: text,
      );
      if (!mounted) return;
      // Close this sheet now that the prompt (if any) has resolved. On
      // `accepted`, the helper has already pushed `/reminder/new`; popping
      // the sheet here just removes the quick-add layer underneath.
      Navigator.of(context).pop();
      if (outcome == ReminderPromptOutcome.declined) {
        // Use the app-level toast stream so the snackbar shows on the
        // HomeShell's ScaffoldMessenger (which persists) and auto-dismisses.
        showAppToast(
          'Saved',
          actionLabel: 'Open',
          onAction: () => appRouter.push('/memory/${mem.id}'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage({required MemorySource sourceType}) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      final mem = await MemoryRepository.instance.createScreenshotMemory(
        source: File(file.path),
        sourceType: sourceType,
      );
      if (mounted) context.push('/memory/${mem.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save image: $e')),
        );
      }
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    _ctrl.text = text;
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file == null) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      final mem = await MemoryRepository.instance.createScreenshotMemory(
        source: File(file.path),
        sourceType: MemorySource.photo,
      );
      if (mounted) context.push('/memory/${mem.id}');
    } catch (_) {
      // Camera unavailable (no permission, no device): silently ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.58,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            child: ListView(
              controller: controller,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'New memory',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        child: Icon(Icons.close_rounded,
                            size: 22, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Title field (item 6) — optional, collapses to a single line
                TextField(
                  controller: _titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Title (optional)',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(DesignTokens.rInput),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    maxLines: null,
                    minLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Type, paste a link, or drop an image…',
                      hintStyle: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.45,
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ),
                const SizedBox(height: 12),
                _CategoryStrip(
                  categories: _allCategories,
                  selected: _selected,
                  onChanged: (c) => setState(() {
                    _selected = c;
                    _userOverrodeCategory = true;
                  }),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _SourceTile(
                      icon: Icons.content_paste_rounded,
                      label: 'Clipboard',
                      onTap: _pasteClipboard,
                    ),
                    const SizedBox(width: 8),
                    _SourceTile(
                      icon: Icons.photo_camera_rounded,
                      label: 'Photo',
                      onTap: _takePhoto,
                    ),
                    const SizedBox(width: 8),
                    _SourceTile(
                      icon: Icons.collections_rounded,
                      label: 'Gallery',
                      onTap: () => _pickImage(sourceType: MemorySource.photo),
                    ),
                    const SizedBox(width: 8),
                    _SourceTile(
                      icon: Icons.screenshot_rounded,
                      label: 'Screenshot',
                      onTap: () =>
                          _pickImage(sourceType: MemorySource.screenshot),
                    ),
                    const SizedBox(width: 8),
                    _SourceTile(
                      icon: Icons.alarm_add_rounded,
                      label: 'Reminder',
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/reminder/new');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal strip of every category (built-in + custom). The auto-picked
/// one is highlighted; tapping a different chip overrides the selection.
///
/// Unlike the old three-chip "Suggested" row, this shows the full list so
/// the user can always route a new memory to any of their categories —
/// including custom ones they created themselves.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<CategoryDef> categories;
  final CategoryDef selected;
  final ValueChanged<CategoryDef> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CATEGORY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '· tap to change',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = categories[i];
              return _CategoryChip(
                category: c,
                selected: c.id == selected.id,
                onTap: () => onChanged(c),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
    final brightness = Theme.of(context).brightness;
    final bg = selected
        ? DesignTokens.chipTint(category.color, brightness)
        : scheme.surfaceContainer;
    final fg = selected ? category.color : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.rChip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(DesignTokens.rChip),
          border: Border.all(
            color: selected
                ? category.color.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(height: 4),
              // Scale text down if the label doesn't fit so "Screenshot"
              // (longest label) never wraps to two lines inside a narrow tile.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
