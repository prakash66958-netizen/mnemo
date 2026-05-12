// Bottom sheet shown when the user shares content into Mnemo from another
// app. Lets them pick a category and optionally add a title before saving.
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/category_service.dart';
import '../../services/share_intent_service.dart';

class SharePreviewSheet extends StatefulWidget {
  const SharePreviewSheet({super.key, required this.pending});
  final PendingShare pending;

  @override
  State<SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<SharePreviewSheet> {
  final _titleCtrl = TextEditingController();
  List<CategoryDef> _categories = const [];
  late CategoryDef _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.pending.suggestedCategory;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final list = await CategoryService.instance.loadAllBrowsable();
    if (!mounted) return;
    setState(() {
      _categories = [
        ...MemoryCategory.values.map((c) => c.toDef()),
        ...list.where((c) => !c.isBuiltin),
      ];
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ShareIntentService.instance.commit(
        widget.pending,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        category: _selected,
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isImage = widget.pending.type == SharedMediaType.image;
    final preview = widget.pending.payload.length > 200
        ? '${widget.pending.payload.substring(0, 200)}…'
        : widget.pending.payload;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Save to Mnemo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            // Preview
            if (isImage && widget.pending.file != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  widget.pending.file!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // Title
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Title (optional)',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
              ),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // Category strip
            Text(
              'CATEGORY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = _categories[i];
                  final active = c.id == _selected.id;
                  return InkWell(
                    onTap: () => setState(() => _selected = c),
                    borderRadius: BorderRadius.circular(DesignTokens.rChip),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? c.color.withValues(alpha: 0.18)
                            : scheme.surfaceContainer,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.rChip),
                        border: Border.all(
                          color: active
                              ? c.color.withValues(alpha: 0.6)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 14, color: c.color),
                          const SizedBox(width: 6),
                          Text(
                            c.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active ? c.color : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
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
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
