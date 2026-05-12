import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/category.dart';

/// Stores and serves user-created categories.
///
/// Persists to SharedPreferences as a single JSON array to keep the surface
/// area tiny — we never expect hundreds of categories. Reads are cached in
/// memory after the first load. Changes broadcast over [changes] so the UI
/// can rebuild without a full provider wiring.
class CategoryService {
  CategoryService._();
  static final CategoryService instance = CategoryService._();

  static const String _prefKey = 'pref_custom_categories';

  final _changesController = StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

  List<CategoryDef>? _cached;

  Future<List<CategoryDef>> loadCustom() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return _cached = const [];
    try {
      final list = jsonDecode(raw) as List;
      _cached = list
          .whereType<Map>()
          .map(_fromJson)
          .whereType<CategoryDef>()
          .toList(growable: false);
      return _cached!;
    } catch (_) {
      return _cached = const [];
    }
  }

  /// Built-ins + custom, with built-ins first. "note" is excluded so it
  /// matches [MemoryCategory.allBrowsable] semantics.
  Future<List<CategoryDef>> loadAllBrowsable() async {
    final custom = await loadCustom();
    return [
      ...MemoryCategory.allBrowsable.map((c) => c.toDef()),
      ...custom,
    ];
  }

  /// Synchronous getter — prefer [loadAllBrowsable] when you can `await`.
  /// Returns built-ins only until [loadCustom] has been awaited at least once.
  List<CategoryDef> allBrowsableSync() => [
        ...MemoryCategory.allBrowsable.map((c) => c.toDef()),
        ...(_cached ?? const []),
      ];

  /// Resolves any stored categoryId (built-in or custom) to a renderable def.
  Future<CategoryDef> resolve(String? id) async {
    if (id == null) return CategoryDef.fallback;
    final builtin = MemoryCategory.values
        .where((c) => c.id == id)
        .cast<MemoryCategory?>()
        .firstWhere((_) => true, orElse: () => null);
    if (builtin != null) return builtin.toDef();
    final custom = await loadCustom();
    for (final c in custom) {
      if (c.id == id) return c;
    }
    return CategoryDef.fallback;
  }

  /// Sync variant used by widgets that need to render on every build. Falls
  /// back to the generic "Note" look if the custom category hasn't been
  /// loaded yet — the stream-driven rebuild fills it in shortly after.
  CategoryDef resolveSync(String? id) {
    if (id == null) return CategoryDef.fallback;
    for (final c in MemoryCategory.values) {
      if (c.id == id) return c.toDef();
    }
    for (final c in _cached ?? const <CategoryDef>[]) {
      if (c.id == id) return c;
    }
    return CategoryDef.fallback;
  }

  /// Creates a custom category from a free-form [name]. Icon is auto-picked
  /// to match the theme; id/color are derived from the name for consistency.
  /// Returns the created (or existing, if a match exists) category.
  Future<CategoryDef> createFromName(String name) async {
    final label = name.trim();
    if (label.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }
    final id = deriveCategoryId(label);

    // Collision with a built-in? Surface it as that built-in instead.
    for (final c in MemoryCategory.values) {
      if (c.id == id) return c.toDef();
    }

    final custom = List<CategoryDef>.from(await loadCustom());
    for (final c in custom) {
      if (c.id == id) return c;
    }

    final def = CategoryDef(
      id: id,
      label: label,
      icon: deriveCategoryIcon(label),
      color: deriveCategoryColor(id),
      isBuiltin: false,
    );
    custom.add(def);
    await _persist(custom);
    return def;
  }

  Future<void> rename(CategoryDef def, String newName) async {
    if (def.isBuiltin) return;
    final list = List<CategoryDef>.from(await loadCustom());
    final idx = list.indexWhere((c) => c.id == def.id);
    if (idx == -1) return;
    list[idx] = CategoryDef(
      id: def.id,
      label: newName.trim().isEmpty ? def.label : newName.trim(),
      icon: deriveCategoryIcon(newName),
      color: def.color,
      isBuiltin: false,
    );
    await _persist(list);
  }

  Future<void> delete(CategoryDef def) async {
    if (def.isBuiltin) return;
    final list = List<CategoryDef>.from(await loadCustom())
      ..removeWhere((c) => c.id == def.id);
    await _persist(list);
  }

  Future<void> _persist(List<CategoryDef> list) async {
    _cached = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(list.map(_toJson).toList()),
    );
    _changesController.add(null);
  }

  // ---------------------------------------------------------------------------
  // JSON helpers — we only persist id/label/color. Icons are re-derived from
  // the label via [deriveCategoryIcon] on load, which keeps all IconData
  // references const in source and preserves Flutter's icon tree-shaking.
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _toJson(CategoryDef c) => {
        'id': c.id,
        'label': c.label,
        'colorValue': c.color.toARGB32(),
      };

  CategoryDef? _fromJson(Map raw) {
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || label is! String) return null;
    final rawColor = raw['colorValue'];
    final color = rawColor is int ? Color(rawColor) : deriveCategoryColor(id);
    return CategoryDef(
      id: id,
      label: label,
      icon: deriveCategoryIcon(label),
      color: color,
      isBuiltin: false,
    );
  }
}
