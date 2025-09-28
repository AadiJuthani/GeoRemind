import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocalendar_gt/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationService {
  // Cooldown logic variables
  final Map<String, DateTime> _lastNotified = {};
  final Duration _cooldown = const Duration(minutes: 30);

  // Local cache of reminders kept in sync via a snapshot listener.
  final List<Map<String, dynamic>> _reminderCache = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remindersSubscription;
  StreamSubscription<User?>? _authSubscription; // <-- auth listener

  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  void startLocationListener() {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // More responsive for a demo
    );

    // Initial subscription to reminders
    _subscribeToReminders();

    // Re-subscribe whenever auth state changes (login/logout)
    _authSubscription ??=
        FirebaseAuth.instance.authStateChanges().listen((_) async {
      // Cancel any existing reminders subscription and re-subscribe for the new user
      await _remindersSubscription?.cancel();
      _remindersSubscription = null;
      _subscribeToReminders();
    });

    Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      debugPrint("User moved to: ${position.latitude}, ${position.longitude}");
      _checkReminders(position);
    });
  }

  void stopLocationListener() {
    _remindersSubscription?.cancel();
    _remindersSubscription = null;

    _authSubscription?.cancel();
    _authSubscription = null;
  }

  void _subscribeToReminders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('LocationService: no signed-in user — not subscribing to reminders.');
      return;
    }

    // Avoid double subscription
    if (_remindersSubscription != null) return;

    _remindersSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('tasks') // <-- per-user tasks collection
        .snapshots()
        .listen((snapshot) {
      _reminderCache.clear();
      for (final doc in snapshot.docs) {
        final data = doc.data();

        GeoPoint? gp;
        final locField = data['location'];
        if (locField is GeoPoint) {
          gp = locField;
        } else if (locField is Map) {
          final lat = (locField['latitude'] ?? locField['lat']) as num?;
          final lng = (locField['longitude'] ?? locField['lng']) as num?;
          if (lat != null && lng != null) gp = GeoPoint(lat.toDouble(), lng.toDouble());
        } else if (data['lat'] != null && data['lng'] != null) {
          gp = GeoPoint((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
        }

        if (gp == null) continue;

        final reminder = <String, dynamic>{
          'id': doc.id,
          'title': data['title'] ?? 'Untitled Reminder',
          'location': gp,
          'radius': (data['radius'] as num?)?.toDouble() ?? 100.0,
        };
        _reminderCache.add(reminder);
      }

      debugPrint('Reminders cache updated: ${_reminderCache.length} items');
    }, onError: (e) {
      debugPrint('Reminders subscription error: $e');
    });
  }

  Future<void> _checkReminders(Position userPosition) async {
    for (final reminder in _reminderCache) {
      try {
        final reminderPoint = reminder['location'] as GeoPoint;
        final radius = (reminder['radius'] as double?) ?? 100.0;
        final id = 'reminder:${reminder['id']}';

        final double distanceInMeters = Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          reminderPoint.latitude,
          reminderPoint.longitude,
        );

        // If user moved well outside the geofence, clear cooldown for this reminder
        if (distanceInMeters > radius + 50) {
          _lastNotified.remove(id);
        }

        // Inside geofence and cooldown has expired -> notify
        if (distanceInMeters < radius && _canNotify(id)) {
          final title = reminder['title'] as String;
          debugPrint('✅ User is close to reminder: "$title". Triggering notification!');

          await NotificationService().showNotification(
            id.hashCode, // unique ID for this notification
            'Reminder Nearby',
            title,
          );

          _markNotified(id);
        }
      } catch (e) {
        debugPrint('Error checking reminder: $e');
      }
    }
  }

  bool _canNotify(String id) {
    final lastNotificationTime = _lastNotified[id];
    if (lastNotificationTime == null) return true;
    return DateTime.now().difference(lastNotificationTime) > _cooldown;
  }

  void _markNotified(String id) {
    _lastNotified[id] = DateTime.now();
  }
}
