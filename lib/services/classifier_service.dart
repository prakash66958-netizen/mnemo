import '../core/category.dart';

/// Rule-based, offline classifier that assigns a [MemoryCategory] to text.
///
/// This is intentionally simple — we match case-insensitive keyword dictionaries
/// per category and pick the category with the highest match score. The
/// dictionaries are bilingual (English + Hinglish) to cover everyday usage
/// patterns in our primary markets. Adding new languages = extending the lists.
class ClassifierService {
  ClassifierService._();
  static final ClassifierService instance = ClassifierService._();

  // Keyword dictionaries. Keep lowercase.
  static const Map<MemoryCategory, List<String>> _keywords = {
    MemoryCategory.reminder: [
      'remind me', 'remind', 'reminder', 'dont forget', "don't forget",
      'yaad dila', 'yaad rakh', 'yaad rakhna', 'mat bhulna', 'bhool mat',
    ],
    MemoryCategory.promise: [
      "i'll", 'i will', 'i shall', 'promise', 'gonna send', 'will send',
      'will call', 'will pay', 'will do', 'will finish', 'will share',
      'bhej dunga', 'bhejunga', 'kar dunga', 'kardunga', 'de dunga',
      'complete kar dunga', 'bata dunga', 'call karunga', 'pay kar dunga',
      'submit kar dunga',
    ],
    MemoryCategory.shopping: [
      'buy', 'purchase', 'shopping', 'order', 'cart', 'amazon', 'flipkart',
      'grocery', 'groceries', 'milk', 'bread', 'vegetables', 'subzi',
      'kharidna', 'lena hai', 'order karna', 'order karo',
    ],
    MemoryCategory.watchLater: [
      'watch', 'youtube', 'youtu.be', 'video', 'movie', 'netflix', 'prime',
      'episode', 'series', 'film', 'trailer', 'hotstar',
      'dekhna hai', 'dekhenge', 'dekhna',
    ],
    MemoryCategory.readLater: [
      'read later', 'article', 'blog', 'post', 'medium.com', 'substack',
      'newsletter', 'essay', 'book', 'chapter', 'paper', 'pdf',
      'padhna hai', 'padhunga', 'padh lunga',
    ],
    MemoryCategory.study: [
      'study', 'exam', 'test', 'syllabus', 'chapter', 'homework', 'assignment',
      'lecture', 'course', 'tutorial', 'notes', 'revision', 'prepare',
      'padhai', 'padhai karni hai', 'padhna',
    ],
    MemoryCategory.work: [
      'meeting', 'standup', 'jira', 'ticket', 'deadline', 'project', 'sprint',
      'client', 'boss', 'manager', 'office', 'presentation', 'deck', 'slack',
      'email', 'invoice', 'report',
    ],
    MemoryCategory.idea: [
      'idea', 'what if', 'thought', 'brainstorm', 'concept', 'prototype',
      'feature idea', 'product idea',
      'soch raha', 'soch rahi', 'dimag mein aaya',
    ],
    MemoryCategory.important: [
      'important', 'urgent', 'asap', 'critical', 'priority', 'high priority',
      'zaroori', 'zaruri', 'bahut zaruri',
    ],
    MemoryCategory.task: [
      'todo', 'to do', 'task', 'complete', 'finish', 'submit', 'send',
      'call', 'email', 'pay', 'book', 'ticket', 'appointment',
      'karna hai', 'complete karna', 'submit karna',
    ],
  };

  /// URL detection takes priority — anything that looks like a link is
  /// classified as [MemoryCategory.link] unless another strong signal overrides.
  static final _urlPattern = RegExp(
    r'(https?:\/\/|www\.)[^\s]+',
    caseSensitive: false,
  );

  /// Returns the most likely category for [text].
  ///
  /// Ties break in favor of higher-priority categories (reminder > promise >
  /// shopping > ...), matching the declaration order in [_keywords].
  MemoryCategory classify(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return MemoryCategory.note;

    final isUrl = _urlPattern.hasMatch(lower);

    int bestScore = 0;
    MemoryCategory? best;

    for (final entry in _keywords.entries) {
      var score = 0;
      for (final kw in entry.value) {
        if (lower.contains(kw)) {
          // Longer keywords are stronger signals.
          score += kw.length > 8 ? 3 : 2;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }

    if (best != null && bestScore >= 2) return best;
    if (isUrl) return MemoryCategory.link;

    // Short, question-like text → idea.
    if (lower.length < 80 && lower.contains('?')) {
      return MemoryCategory.idea;
    }

    return MemoryCategory.note;
  }

  /// Extracts simple tags. We treat explicit #hashtags as tags and also add the
  /// classified category id as a virtual tag for easy filtering.
  List<String> extractTags(String text, MemoryCategory category) {
    final tags = <String>{};
    final hashRegex = RegExp(r'#(\w+)');
    for (final m in hashRegex.allMatches(text)) {
      final tag = m.group(1)?.toLowerCase();
      if (tag != null && tag.isNotEmpty) tags.add(tag);
    }
    tags.add(category.id);
    return tags.toList(growable: false);
  }

  /// Produces the pre-tokenized search corpus stored on MemoryItem.searchTokens.
  /// We normalize, strip punctuation, and de-duplicate.
  List<String> tokenize(String content, {String? title, List<String> tags = const []}) {
    final buffer = StringBuffer()
      ..write(content)
      ..write(' ')
      ..write(title ?? '')
      ..write(' ')
      ..writeAll(tags, ' ');
    final raw = buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s#]', unicode: true), ' ');
    final tokens = raw.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
    return tokens.toList(growable: false);
  }
}
