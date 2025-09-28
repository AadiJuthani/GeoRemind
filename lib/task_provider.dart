// task_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocalendar_gt/task.dart';

class TaskProvider extends ChangeNotifier {
  final List<Task> _tasks = [];
  List<Task> get tasks => List.unmodifiable(_tasks);

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tasksSub;

  String? _uid;
  String? get uid => _uid;

  TaskProvider() {
    // React to login/logout
    _authSub = _auth.authStateChanges().listen((user) {
      _bindToUser(user);
    });
    // Also bind immediately if already signed in
    _bindToUser(_auth.currentUser);
  }

  void _bindToUser(User? user) {
    _tasksSub?.cancel();
    _tasks.clear();
    notifyListeners();

    _uid = user?.uid;
    if (_uid == null) return;

    _tasksSub = _db
        .collection('users')
        .doc(_uid)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      _tasks
        ..clear()
        ..addAll(snap.docs.map((d) => Task.fromDoc(d)));
      notifyListeners();
    });
  }

  CollectionReference<Map<String, dynamic>> _col() {
    final u = _uid ?? _auth.currentUser?.uid;
    if (u == null) {
      throw StateError('No signed-in user; cannot access tasks collection.');
    }
    return _db.collection('users').doc(u).collection('tasks');
  }

  Future<void> addTask(Task t) async {
    final docRef = _col().doc(t.id);
    await docRef.set(t.toMap(forCreate: true), SetOptions(merge: false));
    // Firestore stream will update _tasks; no local add needed.
  }

  /// Deletes ALL tasks for current user (if you have a "reset" action)
  Future<void> clear() async {
    final snap = await _col().get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    // Stream will push an empty list.
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? locationText,
    double? lat,
    double? lng,
  }) async {
    final partial = <String, dynamic>{
      if (title != null) 'title': title,
      if (locationText != null) 'locationText': locationText,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _col().doc(id).set(partial, SetOptions(merge: true));
  }

  Future<void> removeTask(String id) async {
    await _col().doc(id).delete();
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
