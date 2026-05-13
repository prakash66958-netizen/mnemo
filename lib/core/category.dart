import 'package:flutter/material.dart';

/// Canonical, built-in categories used by the on-device classifier and for
/// first-run UX.
///
/// Stored as a string in Isar (via the string field on MemoryItem) so that
/// adding new categories later does not require a schema migration — the
/// unknown value gracefully falls back to [MemoryCategory.note]. User-created
/// custom categories live side-by-side with these, exposed via [CategoryDef]
/// and the CategoryService.
enum MemoryCategory {
  reminder('reminder', 'Remember', Icons.alarm_rounded, Color(0xFFEF4444)),
  promise('promise', 'Promise', Icons.handshake_rounded, Color(0xFFF59E0B)),
  task('task', 'Task', Icons.check_circle_rounded, Color(0xFF10B981)),
  watchLater(
      'watch_later', 'Watch Later', Icons.play_circle_rounded, Color(0xFF8B5CF6)),
  readLater(
      'read_later', 'Read Later', Icons.menu_book_rounded, Color(0xFF06B6D4)),
  shopping(
      'shopping', 'Shopping', Icons.shopping_bag_rounded, Color(0xFFEC4899)),
  study('study', 'Study', Icons.school_rounded, Color(0xFF6366F1)),
  work('work', 'Work', Icons.work_rounded, Color(0xFF0EA5E9)),
  idea('idea', 'Idea', Icons.lightbulb_rounded, Color(0xFFEAB308)),
  important(
      'important', 'Important', Icons.star_rounded, Color(0xFFDC2626)),
  link('link', 'Link', Icons.link_rounded, Color(0xFF3B82F6)),
  note('note', 'Note', Icons.sticky_note_2_rounded, Color(0xFF64748B));

  const MemoryCategory(this.id, this.label, this.icon, this.color);

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  CategoryDef toDef() => CategoryDef(
        id: id,
        label: label,
        icon: icon,
        color: color,
        isBuiltin: true,
        builtin: this,
      );

  static MemoryCategory fromId(String? id) {
    if (id == null) return MemoryCategory.note;
    for (final c in MemoryCategory.values) {
      if (c.id == id) return c;
    }
    return MemoryCategory.note;
  }

  /// Categories shown in the Categories tab grid (excludes generic "note").
  static List<MemoryCategory> get allBrowsable => MemoryCategory.values
      .where((c) => c != MemoryCategory.note)
      .toList(growable: false);
}

/// A category descriptor, either a built-in [MemoryCategory] wrapped in a
/// [CategoryDef] or a user-created one with a custom name.
///
/// The UI layer only ever reads [id], [label], [icon] and [color] — the
/// [builtin] reference is there so places that need identity checks (accent
/// chips, classifier fallbacks) can still compare against the enum.
@immutable
class CategoryDef {
  const CategoryDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.isBuiltin,
    this.builtin,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool isBuiltin;
  final MemoryCategory? builtin;

  /// Generic fallback used when a stored categoryId matches neither a
  /// built-in nor a known custom category. Keeps UI rendering safe.
  static final CategoryDef fallback = MemoryCategory.note.toDef();

  @override
  bool operator ==(Object other) => other is CategoryDef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Infers a theme-matching [IconData] from a free-form category name.
///
/// We look for common words in the label; anything we don't recognize gets a
/// neutral generic icon. Additions here are safe — the map is checked in
/// order, first match wins.
IconData deriveCategoryIcon(String name) {
  final n = name.toLowerCase().trim();
  if (n.isEmpty) return Icons.label_rounded;

  // Order matters: more specific words should come before generic ones.
  const rules = <String, IconData>{
    // Travel / transport
    'travel': Icons.flight_rounded,
    'trip': Icons.card_travel_rounded,
    'flight': Icons.flight_rounded,
    'hotel': Icons.hotel_rounded,
    'car': Icons.directions_car_rounded,
    'bike': Icons.directions_bike_rounded,
    'ride': Icons.directions_car_rounded,
    'drive': Icons.directions_car_rounded,
    'map': Icons.map_rounded,
    // Fitness / health
    'gym': Icons.fitness_center_rounded,
    'fitness': Icons.fitness_center_rounded,
    'workout': Icons.fitness_center_rounded,
    'yoga': Icons.self_improvement_rounded,
    'health': Icons.favorite_rounded,
    'medicine': Icons.medication_rounded,
    'doctor': Icons.local_hospital_rounded,
    'hospital': Icons.local_hospital_rounded,
    'run': Icons.directions_run_rounded,
    // Food / drink
    'food': Icons.restaurant_rounded,
    'recipe': Icons.menu_book_rounded,
    'recipes': Icons.menu_book_rounded,
    'restaurant': Icons.restaurant_rounded,
    'cafe': Icons.local_cafe_rounded,
    'coffee': Icons.local_cafe_rounded,
    'drink': Icons.local_bar_rounded,
    // Money / finance
    'money': Icons.account_balance_wallet_rounded,
    'finance': Icons.account_balance_rounded,
    'bank': Icons.account_balance_rounded,
    'invest': Icons.trending_up_rounded,
    'stock': Icons.show_chart_rounded,
    'bill': Icons.receipt_long_rounded,
    'expense': Icons.payments_rounded,
    'budget': Icons.savings_rounded,
    // Media
    'music': Icons.music_note_rounded,
    'song': Icons.music_note_rounded,
    'podcast': Icons.podcasts_rounded,
    'movie': Icons.movie_rounded,
    'film': Icons.movie_rounded,
    'photo': Icons.photo_camera_rounded,
    'camera': Icons.photo_camera_rounded,
    'game': Icons.sports_esports_rounded,
    // Home / people
    'home': Icons.home_rounded,
    'family': Icons.family_restroom_rounded,
    'kid': Icons.child_care_rounded,
    'baby': Icons.child_care_rounded,
    'pet': Icons.pets_rounded,
    'dog': Icons.pets_rounded,
    'cat': Icons.pets_rounded,
    'plant': Icons.grass_rounded,
    'garden': Icons.yard_rounded,
    // Events
    'birthday': Icons.cake_rounded,
    'cake': Icons.cake_rounded,
    'gift': Icons.card_giftcard_rounded,
    'wedding': Icons.favorite_border_rounded,
    'event': Icons.event_rounded,
    'party': Icons.celebration_rounded,
    'holiday': Icons.beach_access_rounded,
    'vacation': Icons.beach_access_rounded,
    // Work / tech
    'code': Icons.code_rounded,
    'dev': Icons.code_rounded,
    'project': Icons.folder_special_rounded,
    'design': Icons.palette_rounded,
    'email': Icons.mail_rounded,
    'meeting': Icons.groups_rounded,
    'client': Icons.badge_rounded,
    // Education
    'school': Icons.school_rounded,
    'college': Icons.school_rounded,
    'exam': Icons.assignment_rounded,
    'class': Icons.class_rounded,
    'lecture': Icons.cast_for_education_rounded,
    'language': Icons.translate_rounded,
    // Writing / notes
    'quote': Icons.format_quote_rounded,
    'poem': Icons.format_quote_rounded,
    'journal': Icons.book_rounded,
    'diary': Icons.book_rounded,
    'writing': Icons.edit_note_rounded,
    // Misc
    'love': Icons.favorite_rounded,
    'secret': Icons.lock_rounded,
    'password': Icons.password_rounded,
    'dream': Icons.nightlight_round,
    'goal': Icons.flag_rounded,
    'inspiration': Icons.auto_awesome_rounded,
  };

  for (final entry in rules.entries) {
    if (n.contains(entry.key)) return entry.value;
  }
  return Icons.label_rounded;
}

/// Theme-aligned palette for auto-picked category colors.
///
/// These hues pair well with the indigo-seeded Material 3 scheme used in
/// [AppTheme]. We keep the selection deterministic so the same category name
/// always resolves to the same color across launches.
const List<Color> _customCategoryPalette = <Color>[
  Color(0xFF14B8A6), // teal
  Color(0xFF22C55E), // green
  Color(0xFFF97316), // orange
  Color(0xFFA855F7), // violet
  Color(0xFFE11D48), // rose
  Color(0xFF0EA5E9), // sky
  Color(0xFFFACC15), // amber-yellow
  Color(0xFF84CC16), // lime
  Color(0xFFD946EF), // fuchsia
  Color(0xFF64748B), // slate (fallback neutral)
];

Color deriveCategoryColor(String id) {
  if (id.isEmpty) return _customCategoryPalette.last;
  // Simple deterministic hash → palette index.
  var h = 0;
  for (final code in id.codeUnits) {
    h = (h * 31 + code) & 0x7fffffff;
  }
  return _customCategoryPalette[h % _customCategoryPalette.length];
}

/// Normalizes a user-entered category name to a stable id.
String deriveCategoryId(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'custom_${DateTime.now().millisecondsSinceEpoch}' : 'custom_$slug';
}
