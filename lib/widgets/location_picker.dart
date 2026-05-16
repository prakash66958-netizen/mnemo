import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Google Maps Places API key. Same key used by Firebase — ensure the
/// "Places API" is enabled in Google Cloud Console for this project.
const _kMapsApiKey = 'AIzaSyCZKeP_RTnIiqbcU1z6GEVjtHVBPg3ztH4';

/// A bottom sheet that lets the user pick an exact location.
///
/// Supports two flows:
/// 1. "Use current location" — gets GPS coordinates for an exact pin.
/// 2. Type a place name — uses Google Places Text Search to find businesses,
///    POIs, and addresses with exact coordinates.
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
  List<_Place> _suggestions = [];
  _Place? _selectedPlace;

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

  String _buildPinUrl(double lat, double lng) {
    return 'https://www.google.com/maps?q=$lat,$lng';
  }

  String _buildSearchUrl(String name) {
    final encoded = Uri.encodeComponent(name.trim());
    return 'https://www.google.com/maps/search/?api=1&query=$encoded';
  }

  /// Search using Google Places Text Search API.
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
      final encoded = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=$encoded&key=$_kMapsApiKey',
      );

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Search failed. Please try again.';
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';

      if (status == 'REQUEST_DENIED') {
        final errorMsg =
            data['error_message'] as String? ?? 'API request denied';
        setState(() {
          _loading = false;
          _error = errorMsg;
        });
        return;
      }

      if (status != 'OK' && status != 'ZERO_RESULTS') {
        setState(() {
          _loading = false;
          _error = 'Search error: $status';
        });
        return;
      }

      final results = <_Place>[];
      final places = data['results'] as List<dynamic>? ?? [];

      for (final place in places.take(8)) {
        final geo = place['geometry']?['location'];
        if (geo == null) continue;

        final lat = (geo['lat'] as num).toDouble();
        final lng = (geo['lng'] as num).toDouble();
        final name = place['name'] as String? ?? query;
        final address = place['formatted_address'] as String? ?? '';

        results.add(_Place(
          name: name,
          address: address,
          latitude: lat,
          longitude: lng,
        ));
      }

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
        _error = 'Could not search. Check your internet connection.';
      });
    }
  }

  /// Use the device's current GPS location.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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
        mapsUrl: _buildPinUrl(position.latitude, position.longitude),
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
    final deduped = <String>[parts.first];
    for (var i = 1; i < parts.length; i++) {
      if (parts[i] != parts[i - 1]) deduped.add(parts[i]);
    }
    return deduped.join(', ');
  }

  void _selectPlace(_Place place) {
    setState(() => _selectedPlace = place);
  }

  void _confirm() {
    if (_selectedPlace != null) {
      final p = _selectedPlace!;
      Navigator.of(context).pop(LocationResult(
        name: p.name,
        mapsUrl: _buildPinUrl(p.latitude, p.longitude),
        latitude: p.latitude,
        longitude: p.longitude,
      ));
      return;
    }
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
      url = _buildPinUrl(p.latitude, p.longitude);
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
                'Search for a place or use your current GPS location.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('Use current location'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g. PVR Guwahati, Cinepolis...',
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
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
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
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          place.address,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlace(place),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _ctrl,
                builder: (_, val, _) {
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
                      builder: (_, val, _) {
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

class _Place {
  const _Place({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
  final String name;
  final String address;
  final double latitude;
  final double longitude;
}
