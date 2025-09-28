// email_scanner.dart
// A self-contained service + minimal UI gate to ensure Firebase auth
// happens BEFORE any navigation or Firestore writes.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// --------------- SERVICE ---------------

class EmailScannerService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/gmail.readonly',
    ],
  );

  /// Signs into Google and then Firebase. Returns the Firebase [User] on success.
  Future<User?> signInWithGoogleAndFirebase() async {
    try {
      // 1) Google account
      final account = _googleSignIn.currentUser ?? await _googleSignIn.signIn();
      if (account == null) {
        debugPrint('[EmailScanner] Google sign-in cancelled.');
        return null;
      }

      // 2) Tokens
      final auth = await account.authentication;
      if (auth.idToken == null || auth.accessToken == null) {
        debugPrint('[EmailScanner] Missing Google tokens.');
        return null;
      }

      // 3) Firebase credential
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );

      // 4) Firebase sign-in
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user ?? FirebaseAuth.instance.currentUser;

      if (user == null) {
        debugPrint('[EmailScanner] Firebase user is null after sign-in.');
        return null;
      }

      // Optional: prove token is valid
      await user.getIdToken(true);
      debugPrint('[EmailScanner] Signed into Firebase as: ${user.uid}');
      return user;
    } catch (e, st) {
      debugPrint('[EmailScanner] Firebase sign-in failed: $e\n$st');
      return null;
    }
  }

  /// Fetches recent Gmail messages and creates "reminders" in Firestore
  /// for emails that look like reminders/meetings—ONLY after auth confirmed.
  Future<void> scanAndCreateReminders() async {
    final user = FirebaseAuth.instance.currentUser ??
        await signInWithGoogleAndFirebase();

    if (user == null) {
      debugPrint('[EmailScanner] Aborting: not authenticated.');
      return;
    }

    // Get Google access token (from GoogleSignIn)
    final account =
        _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) {
      debugPrint('[EmailScanner] No Google account available post-auth.');
      return;
    }
    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) {
      debugPrint('[EmailScanner] Missing Gmail access token.');
      return;
    }

    // ---- Gmail list ----
    final listResp = await http.get(
      Uri.parse(
          'https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=50'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (listResp.statusCode != 200) {
      debugPrint('[EmailScanner] Gmail list failed: '
          '${listResp.statusCode} ${listResp.body}');
      return;
    }

    final listData = json.decode(listResp.body) as Map<String, dynamic>;
    final messages =
        (listData['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    debugPrint('[EmailScanner] Found ${messages.length} messages to inspect');

    for (final msg in messages) {
      final id = msg['id'] as String?;
      if (id == null) continue;

      // Skip if already parsed
      final existing = await FirebaseFirestore.instance
          .collection('parsedMessages')
          .doc(id)
          .get();
      if (existing.exists) continue;

      // ---- Gmail message ----
      final mResp = await http.get(
        Uri.parse(
            'https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (mResp.statusCode != 200) continue;

      final mData = json.decode(mResp.body) as Map<String, dynamic>;
      final payload = mData['payload'] as Map<String, dynamic>?;
      final headers =
          (payload?['headers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      String subject = '';
      String from = '';
      for (final h in headers) {
        final name = (h['name'] as String?)?.toLowerCase();
        if (name == 'subject') subject = h['value'] as String? ?? '';
        if (name == 'from') from = h['value'] as String? ?? '';
      }

      final snippet = mData['snippet'] as String? ?? '';
      final lower = '$subject\n$snippet'.toLowerCase();

      if (lower.contains('remind') ||
          lower.contains('reminder') ||
          lower.contains('meeting') ||
          lower.contains('appointment')) {
        final doc = {
          'title': subject.isNotEmpty ? subject : 'Email reminder from $from',
          'sourceEmailId': id,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        };

        try {
          await FirebaseFirestore.instance.collection('reminders').add(doc);
          await FirebaseFirestore.instance
              .collection('parsedMessages')
              .doc(id)
              .set({
            'parsedAt': FieldValue.serverTimestamp(),
            'by': user.uid,
          });

          debugPrint(
              '[EmailScanner] Created reminder from email: $id -> ${doc['title']}');
        } catch (e) {
          debugPrint('[EmailScanner] Firestore write failed: $e');
        }
      }
    }
  }
}

/// --------------- MINIMAL UI GATE ---------------
/// Use this as your app’s "root" to ensure you never navigate past login
/// before Firebase reports an authenticated user.

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;

        // If already signed in, allow app to continue (replace with your app's home)
        if (user != null) {
          return const Scaffold(
            body: Center(child: Text('Signed in')), // TODO: replace with your Home widget
          );
        }

        // Not signed in: show a simple sign-in UI
        return Scaffold(
          appBar: AppBar(title: const Text('Sign in')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sign in with Google to enable email scanning'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                    onPressed: () async {
                      final service = EmailScannerService();
                      final u = await service.signInWithGoogleAndFirebase();
                      if (u != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signed in')),
                        );
                        // Optionally run a scan now
                        await service.scanAndCreateReminders();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sign-in failed')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
