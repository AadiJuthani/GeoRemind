// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:geocalendar_gt/task_provider.dart';
import 'package:geocalendar_gt/home_with_map.dart';
import 'package:geocalendar_gt/add_task.dart';
import 'package:geocalendar_gt/notification_service.dart';
import 'package:geocalendar_gt/location.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:geocalendar_gt/firebase_options.dart';
import 'package:geocalendar_gt/task.dart';
import 'package:geocalendar_gt/gt_buildings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notifications
  await NotificationService().init();

  // Start location listener (it will check permissions itself)
  LocationService().startLocationListener();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TaskProvider(),
      child: MaterialApp(
        title: 'GeoRemind',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurpleAccent,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0B0E14),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            filled: true,
            fillColor: Color(0xFF0F1720),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),

        // Don’t route to /home until Firebase says we’re signed in.
        home: const AuthGate(),

        routes: {
          '/home': (c) => const HomeWithMap(),
          '/add': (c) => const AddTaskScreen(),
        },
      ),
    );
  }
}

/// AuthGate shows LoginScreen when signed out, HomeWithMap when signed in.
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
        if (user == null) {
          return const LoginScreen();
        }

        // Signed in → show your app
        return const HomeWithMap();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Pick Google account (or reuse)
      final googleSignIn = GoogleSignIn(
        scopes: [
          'email',
          // If you use Gmail API in-app, keep this:
          'https://www.googleapis.com/auth/gmail.readonly',
        ],
      );

      final account = await (googleSignIn.currentUser != null
          ? googleSignIn.signInSilently()
          : googleSignIn.signIn());

      if (account == null) {
        setState(() {
          _error = 'Sign-in cancelled.';
          _loading = false;
        });
        return;
      }

      // 2) Get tokens
      final auth = await account.authentication;
      if (auth.idToken == null || auth.accessToken == null) {
        setState(() {
          _error = 'Missing Google tokens.';
          _loading = false;
        });
        return;
      }

      // 3) Sign into Firebase
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Optional: ensure token is valid
      await userCred.user?.getIdToken(true);

      // ✅ Do NOT navigate here.
      // AuthGate rebuilds automatically to HomeWithMap when authStateChanges emits.
    } catch (e) {
      setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  "Welcome to GeoRemind",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text("Continue with Google"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    final consent = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Demo scan'),
                        content: const Text(
                            'Allow a demo email scan that adds a sample task?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('No')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Yes')),
                        ],
                      ),
                    );

                    if (consent == true) {
                      setState(() => _loading = true);
                      try {
                        // Fake 3–4 second scan delay
                        await Future.delayed(const Duration(seconds: 3));

                        // Pick “Student Center” (interpreting your “tech center”) or fallback
                        final pickup = kGtBuildings.firstWhere(
                          (b) => b.name.toLowerCase().contains('student center'),
                          orElse: () => kGtBuildings.first,
                        );

                        // Create the demo task
                        final demoTask = Task(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: 'Your Delivery Package is here',
                          locationText: pickup.name,
                          lat: pickup.lat,
                          lng: pickup.lng,
                        );

                        if (mounted) {
                          context.read<TaskProvider>().addTask(demoTask);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added demo task: "${demoTask.title}"'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Demo scan failed: $e');
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text("Sign in with Email"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
