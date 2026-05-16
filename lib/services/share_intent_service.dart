// Listens for the Android "Share to Mnemo" intent and queues incoming
// payloads for the user to confirm with a category picker before saving.
import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/category.dart';
import '../models/memory_item.dart';
import '../services/classifier_service.dart';
import 'memory_repository.dart';

/// A share the user kicked off from another app, queued for the user to
/// confirm with a category + title before it becomes a MemoryItem.
class PendingShare {
  PendingShare({required this.type, required this.payload, this.file});
  final SharedMediaType type;
  final String payload;
  final File? file;

  /// Auto-detected category based on the text payload (for text/url types).
  CategoryDef get suggestedCategory {
    if (type == SharedMediaType.text || type == SharedMediaType.url) {
      return ClassifierService.instance.classify(payload).toDef();
    }
    return MemoryCategory.note.toDef();
  }
}

class ShareIntentService {
  ShareIntentService._();
  static final ShareIntentService instance = ShareIntentService._();

  StreamSubscription<List<SharedMediaFile>>? _sub;
  final _onNewMemory = StreamController<MemoryItem>.broadcast();
  final _pending = StreamController<PendingShare>.broadcast();

  /// Fires whenever a new memory is created from a share intent, so the UI
  /// can show a confirmation snackbar or navigate.
  Stream<MemoryItem> get onNewMemory => _onNewMemory.stream;

  /// Fires when a share arrives and needs user confirmation (category pick).
  Stream<PendingShare> get pendingShare => _pending.stream;

  Future<void> start() async {
    // 1) Cold start: app was launched by a share.
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      _enqueue(initial);
      ReceiveSharingIntent.instance.reset();
    }

    // 2) Warm: app already running.
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(_enqueue);
  }

  void _enqueue(List<SharedMediaFile> shared) {
    for (final s in shared) {
      switch (s.type) {
        case SharedMediaType.text:
        case SharedMediaType.url:
          final content = s.path;
          if (content.trim().isEmpty) continue;
          _pending.add(PendingShare(type: s.type, payload: content));
        case SharedMediaType.image:
          final file = File(s.path);
          _pending.add(PendingShare(type: s.type, payload: s.path, file: file));
        case SharedMediaType.video:
        case SharedMediaType.file:
          _pending.add(PendingShare(type: s.type, payload: s.path));
      }
    }
  }

  /// Called by the UI after the user confirms category + title in the picker.
  Future<MemoryItem> commit(
    PendingShare p, {
    String? title,
    CategoryDef? category,
  }) async {
    final forcedCategory = category?.builtin;
    final forcedCategoryId =
        (category != null && !category.isBuiltin) ? category.id : null;

    MemoryItem mem;
    switch (p.type) {
      case SharedMediaType.text:
      case SharedMediaType.url:
        mem = await MemoryRepository.instance.createTextMemory(
          content: p.payload,
          title: title,
          source: MemorySource.share,
          forcedCategory: forcedCategory,
          forcedCategoryId: forcedCategoryId,
        );
      case SharedMediaType.image:
        mem = await MemoryRepository.instance.createTextMemory(
          content: 'Image shared: ${p.payload}',
          title: title,
          source: MemorySource.share,
          forcedCategory: forcedCategory,
          forcedCategoryId: forcedCategoryId,
        );
      case SharedMediaType.video:
      case SharedMediaType.file:
        mem = await MemoryRepository.instance.createTextMemory(
          content: p.payload,
          title: title,
          source: MemorySource.share,
          forcedCategory: forcedCategory,
          forcedCategoryId: forcedCategoryId,
        );
    }
    _onNewMemory.add(mem);
    return mem;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
