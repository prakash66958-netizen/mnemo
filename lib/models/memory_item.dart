import 'package:isar/isar.dart';

part 'memory_item.g.dart';

/// Types of content a memory item can represent.
enum MemorySource {
  text, // manually typed note
  link, // URL or link
  clipboard, // captured from clipboard
  share, // received via Android share intent
  screenshot, // image with OCR text (typically from the gallery)
  photo, // user-captured photo (camera or gallery) — image first, text optional
}

/// Primary persisted entity for everything the user saves.
///
/// The data model is intentionally flat so Isar queries stay cheap:
/// - [content] is the main searchable body (text or OCR result)
/// - [rawUrl] is populated if the item is a link
/// - [imagePath] points to a copied-in screenshot on disk
/// - [categoryId] mirrors `MemoryCategory.id` to avoid schema churn if we add
///   new categories later
/// - [tags] is a plain list of lowercase strings for cheap tag filtering
/// - [searchTokens] is a pre-tokenized lowercase form used for fuzzy search
@collection
class MemoryItem {
  Id id = Isar.autoIncrement;

  /// Optional user-provided title, short and punchy.
  String? title;

  @Index(type: IndexType.value, caseSensitive: false)
  late String content;

  String? rawUrl;

  String? imagePath;

  @Index()
  late String sourceType; // MemorySource.name

  @Index(caseSensitive: false)
  late String categoryId; // MemoryCategory.id

  /// Secondary tags (lowercase, no '#' prefix).
  List<String> tags = const [];

  /// Pre-tokenized lowercase content + title + tags, used for search.
  @Index(type: IndexType.value, caseSensitive: false)
  List<String> searchTokens = const [];

  @Index()
  late DateTime createdAt;

  @Index()
  late DateTime updatedAt;

  @Index()
  bool pinned = false;

  @Index()
  bool archived = false;

  /// True when the classifier detected future intent ("I'll send tomorrow").
  bool hasPromise = false;

  /// True when the user has already accepted/dismissed the reminder prompt.
  bool reminderPromptHandled = false;

  /// Optional color override if the user wants a non-default card tint.
  int? colorValue;
}
