import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../models/memory_item.dart';

/// Outbound sharing — sends a saved [MemoryItem] or a backup file to another
/// app via the Android share sheet. Paired with [ShareIntentService] which
/// handles the inbound direction.
class ShareOutService {
  ShareOutService._();
  static final ShareOutService instance = ShareOutService._();

  /// Shares a memory's content (and image, if any) to another app.
  Future<ShareResult> shareMemory(MemoryItem m) async {
    final imagePath = m.imagePath;
    final hasImage = imagePath != null && await File(imagePath).exists();

    final body = (m.title != null && m.title!.trim().isNotEmpty)
        ? '${m.title}\n\n${m.content}'
        : m.content;
    final subject = (m.title?.trim().isNotEmpty ?? false)
        ? m.title!
        : (m.content.length > 60 ? m.content.substring(0, 60) : m.content);

    if (hasImage) {
      return Share.shareXFiles(
        [XFile(imagePath)],
        text: body,
        subject: subject,
      );
    }
    return Share.share(body, subject: subject);
  }

  /// Shares a file (e.g. a backup JSON) via the system share sheet so the
  /// user can pick Google Drive, Gmail, Files, Bluetooth, etc.
  Future<ShareResult> shareFile(
    File file, {
    String? subject,
    String? text,
  }) async {
    return Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: text,
    );
  }
}
