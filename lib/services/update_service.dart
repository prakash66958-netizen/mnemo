import 'dart:convert';
import 'dart:io';

import '../core/constants/app_constants.dart';

/// Result of a release check against the GitHub Releases API.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.body,
    required this.apkUrl,
    required this.htmlUrl,
    required this.publishedAt,
  });

  /// Raw tag, e.g. "v2.1.0".
  final String tagName;

  /// Cleaned version string, e.g. "2.1.0".
  final String version;

  /// Markdown release notes / changelog.
  final String body;

  /// Direct download URL for the APK asset (if attached), otherwise empty.
  final String apkUrl;

  /// GitHub release page URL — fallback when no APK asset is found.
  final String htmlUrl;

  final DateTime publishedAt;

  /// True when [version] is strictly newer than [AppConstants.appVersion].
  bool get isNewer => _compare(version, AppConstants.appVersion) > 0;

  static int _compare(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    for (var i = 0; i < 3; i++) {
      final diff = (pa[i]) - (pb[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }

  static List<int> _parts(String v) {
    final clean = v.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts = clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}

/// Checks the GitHub Releases API for the latest Mnemo release.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _apiUrl =
      'https://api.github.com/repos/${AppConstants.githubRepo}/releases/latest';

  /// Fetches the latest release. Throws on network / parse errors.
  Future<ReleaseInfo> fetchLatest() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'Mnemo-App/${AppConstants.appVersion}');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
            'GitHub API returned ${response.statusCode}', uri: Uri.parse(_apiUrl));
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tagName = (json['tag_name'] as String? ?? '').trim();
      final version = tagName.replaceAll(RegExp(r'^v'), '');
      final notes = (json['body'] as String? ?? '').trim();
      final htmlUrl = (json['html_url'] as String? ?? '').trim();
      final publishedAt = DateTime.tryParse(
              json['published_at'] as String? ?? '') ??
          DateTime.now();

      // Find the APK asset URL (first .apk asset in the release).
      String apkUrl = '';
      final assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl =
              (asset['browser_download_url'] as String? ?? '').trim();
          break;
        }
      }

      return ReleaseInfo(
        tagName: tagName,
        version: version,
        body: notes,
        apkUrl: apkUrl,
        htmlUrl: htmlUrl,
        publishedAt: publishedAt,
      );
    } finally {
      client.close();
    }
  }
}
