import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// A bottom sheet that lets the user pick an exact location.
///
/// Supports two flows:
/// 1. "Use current location" — gets GPS coordinates for an exact pin.
/// 2. Type a place name — geocodes it to get exact lat/lng coordinates
///    so the Maps link pins the precise spot, not a search results page.
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
  const LocationResult({
    required this.name,
    required this.mapsUrl,
    this.latitude,
    this.longitude,
  });
  final String name;
  final String mapsUrl;
  final double? latitude;
  final double? longitude;
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({this.initialName});
  final String? initialName;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late final TextEditingController _ctrl;
  bool _loading = false;
  String? _error;
  List<_GeocodedPlace> _suggestions = [];
  _GeocodedPlace? _selectedPlace;

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

  /// Builds an exact-pin Google Maps URL using coordinates.
  String _buildPinUrl(double lat, double lng, String label) {
    // This format drops a pin at the exact coordinates.
    return 'https://www.google.com/maps?q=$lat,$lng';
  }

  /// Fallback: search-based URL when we don't have coordinates.
  String _buildSearchUrl(String name) {
    final encoded = Uri.encodeComponent(name.trim());
    return 'https://www.google.com/maps/search/?api=1&query=$encoded';
  }

  /// Geocode the typed text to get coordinate suggestions.
  Future<void> _search() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _suggestions = [];
      _selectedPlace = null;
    });

    try {
      final locations = await locationFromAddress(query);
      final results = <_GeocodedPlace>[];

      for (final loc in locations.take(5)) {
        // Reverse geocode to get a readable address for each result.
        String address = query;
        try {
          final placemarks =
              await placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (placemarks.isNotEmpty) {
            address = _formatPlacemark(placemarks.first, query);
          }
        } catch (_) {
          // Keep the original query as the name.
        }
        results.add(_GeocodedPlace(
          name: address,
          latitude: loc.latitude,
          longitude: loc.longitude,
        ));
      }

      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
        if (results.isEmpty) {
          _error = 'No locations found for "$query"';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not find location. Check your connection.';
      });
    }
  }

  String _formatPlacemark(Placemark p, String fallback) {
    final parts = <String>[];
    if (p.name != null && p.name!.isNotEmpty && p.name != p.postalCode) {
      parts.add(p.name!);
    }
    if (p.subLocality != null && p.subLocality!.isNotEmpty) {
      parts.add(p.subLocality!);
    }
    if (p.locality != null && p.locality!.isNotEmpty) {
      parts.add(p.locality!);
    }
    if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
      parts.add(p.administrativeArea!);
    }
    if (parts.isEmpty) return fallback;
    // Deduplicate consecutive entries.
    final deduped = <String>[parts.first];
    for (var i = 1; i < parts.length; i++) {
      if (parts[i] != parts[i - 1]) deduped.add(parts[i]);
    }
    return deduped.join(', ');
  }

  /// Use the device's current GPS location.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Check permissions.
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _loading = false;
            _error = 'Location permission denied.';
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error = 'Location permission permanently denied. '
              'Enable it in Settings.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Reverse geocode for a human-readable name.
      String name = '${position.latitude.toStringAsFixed(5)}, '
          '${position.longitude.toStringAsFixed(5)}';
      try {
        final placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          name = _formatPlacemark(placemarks.first, name);
        }
      } catch (_) {}

      if (!mounted) return;

      final result = LocationResult(
        name: name,
        mapsUrl: _buildPinUrl(position.latitude, position.longitude, name),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not get location. Make sure GPS is enabled.';
      });
    }
  }

  void _selectPlace(_GeocodedPlace place) {
    setState(() => _selectedPlace = place);
  }

  void _confirm() {
    if (_selectedPlace != null) {
      final p = _selectedPlace!;
      Navigator.of(context).pop(LocationResult(
        name: p.name,
        mapsUrl: _buildPinUrl(p.latitude, p.longitude, p.name),
        latitude: p.latitude,
        longitude: p.longitude,
      ));
      return;
    }
    // Fallback: if no geocoded place selected, use search URL.
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(LocationResult(
      name: name,
      mapsUrl: _buildSearchUrl(name),
    ));
  }

  Future<void> _preview() async {
    String url;
    if (_selectedPlace != null) {
      final p = _selectedPlace!;
      url = _buildPinUrl(p.latitude, p.longitude, p.name);
    } else {
      final name = _ctrl.text.trim();
      if (name.isEmpty) return;
      url = _buildSearchUrl(name);
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
                'Search for a place or use your current GPS location for '
                'an exact pin.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              // Current location button.
              OutlinedButton.icon(
                onPressed: _loading ? null : _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('Use current location'),
              ),
              const SizedBox(height: 12),
              // Search field.
              Row(
                children: [
                  Expanded(
                    child: TextField(
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
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search',
                  ),
                ],
              ),
              // Loading indicator.
              if (_loading) ...[
                const SizedBox(height: 12),
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
              // Error message.
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
              // Search results.
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final place = _suggestions[i];
                      final selected = _selectedPlace == place;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor:
                            scheme.primaryContainer.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Icon(
                          selected
                              ? Icons.location_on_rounded
                              : Icons.location_on_outlined,
                          color: selected ? scheme.primary : null,
                          size: 20,
                        ),
                        title: Text(
                          place.name,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${place.latitude.toStringAsFixed(4)}, '
                          '${place.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        onTap: () => _selectPlace(place),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Preview button.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _ctrl,
                builder: (_, val, __) {
                  final hasContent =
                      val.text.trim().isNotEmpty || _selectedPlace != null;
                  return OutlinedButton.icon(
                    onPressed: hasContent ? _preview : null,
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
                      builder: (_, val, __) {
                        final canConfirm = _selectedPlace != null ||
                            val.text.trim().isNotEmpty;
                        return FilledButton(
                          onPressed: canConfirm ? _confirm : null,
                          child: Text(_selectedPlace != null
                              ? 'Set exact location'
                              : 'Set location'),
                        );
                      },
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

class _GeocodedPlace {
  const _GeocodedPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
  final String name;
  final double latitude;
  final double longitude;
}
