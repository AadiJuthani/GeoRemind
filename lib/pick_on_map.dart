import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geocalendar_gt/google_api_key.dart';
import 'package:uuid/uuid.dart';

class PickOnMapScreen extends StatefulWidget {
  final LatLng initial;
  const PickOnMapScreen({super.key, required this.initial});

  @override
  State<PickOnMapScreen> createState() => _PickOnMapScreenState();
}

class _PickOnMapScreenState extends State<PickOnMapScreen> {
  LatLng? _picked;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<_AutoCandidate> _results = [];
  String? _sessionToken;
  String? _selectedName;
  String? _lastRawResponse;

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (q.trim().isEmpty) return setState(() => _results = []);
      _searchPlaces(q.trim());
    });
  }

  Future<void> _searchPlaces(String query) async {
    // ensure we have a session token for autocomplete requests
    _sessionToken ??= const Uuid().v4();
    final params = <String, String>{
      'input': query,
      'key': kGoogleMapsApiKey,
      'sessiontoken': _sessionToken!,
      // Use explicit location+radius and strictbounds to bias to the map center (Places API pattern)
    };
    final init = widget.initial;
    try {
      params['location'] = '${init.latitude},${init.longitude}';
      params['radius'] = '2000'; // 2km radius
      params['strictbounds'] = 'true';
      // prefer establishment results (buildings, POIs)
      params['types'] = 'establishment';
    } catch (_) {}
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );
    try {
      final resp = await http.get(url);
      _lastRawResponse = resp.body;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status == 'OK') {
          final predictions = (data['predictions'] as List)
              .cast<Map<String, dynamic>>();
          final parsed = predictions.map((p) {
            final structured =
                p['structured_formatting'] as Map<String, dynamic>?;
            final main =
                structured?['main_text'] as String? ??
                (p['description'] as String? ?? '');
            final secondary = structured?['secondary_text'] as String? ?? '';
            return _AutoCandidate(
              description: p['description'] as String? ?? '',
              placeId: p['place_id'] as String? ?? '',
              mainText: main,
              secondaryText: secondary,
            );
          }).toList();
          setState(() => _results = parsed);
        } else {
          setState(() => _results = []);
        }
      } else {
        setState(() => _results = []);
      }
    } catch (e) {
      _lastRawResponse = 'error: $e';
      setState(() => _results = []);
    }
  }

  Future<_PlaceDetails?> _fetchPlaceDetails(
    String placeId,
    String? sessionToken,
  ) async {
    final url =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': placeId,
          'key': kGoogleMapsApiKey,
          'sessiontoken': sessionToken ?? '',
          'fields': 'name,geometry,formatted_address',
        });
    try {
      final resp = await http.get(url);
      _lastRawResponse = resp.body;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status == 'OK') {
          final result = data['result'] as Map<String, dynamic>?;
          if (result == null) return null;
          final name = result['name'] as String?;
          final loc =
              (result['geometry']?['location']) as Map<String, dynamic>?;
          final lat = (loc?['lat'] as num?)?.toDouble();
          final lng = (loc?['lng'] as num?)?.toDouble();
          final formatted = result['formatted_address'] as String?;
          if (lat == null || lng == null) return null;
          return _PlaceDetails(
            name: name,
            lat: lat,
            lng: lng,
            formattedAddress: formatted,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick location'),
        actions: [
          IconButton(
            tooltip: 'Debug responses',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Last API response'),
                  content: SingleChildScrollView(
                    child: Text(_lastRawResponse ?? 'No response yet'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          TextButton(
            onPressed: _picked == null
                ? null
                : () {
                    Navigator.of(context).pop(_picked);
                  },
            child: const Text('Select', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Search places (e.g. "Klaus Advanced Computing Building")',
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) async {
                    // If user presses Enter, select the first suggestion if present
                    if (_results.isNotEmpty) {
                      final r = _results.first;
                      final details = await _fetchPlaceDetails(
                        r.placeId,
                        _sessionToken,
                      );
                      if (details != null) {
                        final latlng = LatLng(details.lat, details.lng);
                        await _mapController?.animateCamera(
                          CameraUpdate.newLatLng(latlng),
                        );
                        setState(() {
                          _picked = latlng;
                          _results = [];
                          _selectedName = details.name ?? r.description;
                          _searchCtrl.text = _selectedName!;
                        });
                      }
                      _sessionToken = null;
                    }
                  },
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: widget.initial,
                        zoom: 15,
                      ),
                      onMapCreated: (c) => _mapController = c,
                      onTap: (latlng) {
                        setState(() => _picked = latlng);
                      },
                      markers: _picked == null
                          ? {}
                          : {
                              Marker(
                                markerId: const MarkerId('picked'),
                                position: _picked!,
                              ),
                            },
                    ),
                    if (_results.isNotEmpty)
                      Positioned(
                        top: 64,
                        left: 12,
                        right: 12,
                        child: Card(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _results.length,
                              itemBuilder: (c, i) {
                                final r = _results[i];
                                return ListTile(
                                  title: RichText(
                                    text: TextSpan(
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                      children: [
                                        TextSpan(
                                          text: r.mainText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (r.secondaryText.isNotEmpty)
                                          TextSpan(
                                            text: '\n${r.secondaryText}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  isThreeLine: r.secondaryText.isNotEmpty,
                                  onTap: () async {
                                    // fetch place details for geometry
                                    final details = await _fetchPlaceDetails(
                                      r.placeId,
                                      _sessionToken,
                                    );
                                    if (details != null) {
                                      final latlng = LatLng(
                                        details.lat,
                                        details.lng,
                                      );
                                      await _mapController?.animateCamera(
                                        CameraUpdate.newLatLng(latlng),
                                      );
                                      setState(() {
                                        _picked = latlng;
                                        _results = [];
                                        _selectedName =
                                            details.name ?? r.description;
                                        _searchCtrl.text = _selectedName!;
                                      });
                                    }
                                    // clear session token after a selection
                                    _sessionToken = null;
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_picked != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'Lat: ${_picked!.latitude.toStringAsFixed(6)}, Lng: ${_picked!.longitude.toStringAsFixed(6)}',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AutoCandidate {
  final String description;
  final String placeId;
  final String mainText;
  final String secondaryText;
  _AutoCandidate({
    required this.description,
    required this.placeId,
    this.mainText = '',
    this.secondaryText = '',
  });
}

class _PlaceDetails {
  final String? name;
  final double lat;
  final double lng;
  final String? formattedAddress;

  _PlaceDetails({
    this.name,
    required this.lat,
    required this.lng,
    this.formattedAddress,
  });
}
