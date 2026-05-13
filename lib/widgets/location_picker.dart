import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A bottom sheet that lets the user type a location name.
/// Generates a Google Maps search URL from the name so the recipient
/// can tap it and navigate directly.
///
/// Returns a [LocationResult] or null if the user cancelled.
Future<LocationResult?> showLocationPicker(BuildContext context,
    {String? initialName}) async {
  return showModalBottomSheet<LocationResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LocationPickerSheet(initialName: initialName),
  );
}

class LocationResult {
  const LocationResult({required this.name, required this.mapsUrl});
  final String name;
  final String mapsUrl;
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({this.initialName});
  final String? initialName;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _buildMapsUrl(String name) {
    final encoded = Uri.encodeComponent(name.trim());
    return 'https://www.google.com/maps/search/?api=1&query=$encoded';
  }

  void _confirm() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      LocationResult(name: name, mapsUrl: _buildMapsUrl(name)),
    );
  }

  Future<void> _preview() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final url = Uri.parse(_buildMapsUrl(name));
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.location_on_rounded,
                      color: scheme.primary, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Add location',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Type a place name. A Google Maps link will be attached so '
                'anyone you share with can navigate there.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Cinepolis, Mumbai',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 12),
              // Preview button
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _ctrl,
                builder: (_, val, __) {
                  final hasText = val.text.trim().isNotEmpty;
                  return OutlinedButton.icon(
                    onPressed: hasText ? _preview : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Preview on Google Maps'),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctrl,
                      builder: (_, val, __) => FilledButton(
                        onPressed:
                            val.text.trim().isNotEmpty ? _confirm : null,
                        child: const Text('Set location'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
