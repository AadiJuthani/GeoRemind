import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // iOS/macOS: If you want to handle taps while app is terminated/backgrounded,
    // also consider onDidReceiveBackgroundNotificationResponse with a top-level handler.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      // If you want the OS to ask at init time (optional; we also call requestPermissions below)
      // requestAlertPermission: true,
      // requestSoundPermission: true,
      // requestBadgePermission: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: darwinInit, macOS: darwinInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // handle tap
        // final payload = resp.payload;
      },
      // onDidReceiveBackgroundNotificationResponse: yourTopLevelHandler, // optional
    );

    // ===== Ask for permissions explicitly on each platform =====

    // iOS
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // macOS
    await _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Android 13+ runtime permission
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestPermission();
  }

  Future<void> showNotification(int id, String title, String body) async {
    // ANDROID
    const androidDetails = AndroidNotificationDetails(
      'georemind_channel',
      'GeoRemind',
      channelDescription: 'Notifications for nearby reminders',
      importance: Importance.high,
      priority: Priority.high,
    );

    // iOS/macOS — make it show while the app is in the foreground
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,   // <— THIS makes banners/alerts appear in foreground
      presentSound: true,
      presentBadge: true,
    );

    const notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(id, title, body, notifDetails);
  }
}
