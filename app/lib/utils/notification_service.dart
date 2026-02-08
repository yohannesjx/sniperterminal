import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Notification Service for Background Alerts
/// Handles push notifications when app is backgrounded or phone is locked
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialize notification service
  /// Call this on app startup
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize plugin
      await _notifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request permissions (Android 13+)
      await _requestPermissions();

      // Create high-importance notification channel (Android)
      await _createNotificationChannel();

      _initialized = true;
      print('🔔 NotificationService initialized successfully');
    } catch (e) {
      print('⚠️ NotificationService initialization failed: $e');
      print('⚠️ Notifications will be disabled (this is normal on simulator)');
      _initialized = false;
    }
  }

  /// Request notification permissions (Android 13+, iOS)
  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        print('🔔 Android notification permission: ${granted ?? false}');
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        print('🔔 iOS notification permission: ${granted ?? false}');
      }
    }
  }

  /// Create high-importance notification channel (Android)
  /// This ensures notifications vibrate/make sound even when phone is locked
  Future<void> _createNotificationChannel() async {
    final channel = AndroidNotificationChannel(
      'whale_alerts', // ID
      'Whale Alerts', // Name
      description: 'Critical whale activity notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]), // Vibration pattern
      showBadge: true,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      print('🔔 Created high-importance notification channel');
    }
  }

  /// Show a notification
  /// 
  /// [title] - Notification title (e.g., "BTC Whale Alert 🚨")
  /// [body] - Notification body (e.g., "A $1.5M buy order detected at $98,500")
  Future<void> showNotification(String title, String body) async {
    if (!_initialized) {
      print('⚠️ NotificationService not initialized, skipping notification');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'whale_alerts', // Must match channel ID
      'Whale Alerts',
      channelDescription: 'Critical whale activity notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Generate unique ID based on timestamp
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );

    print('🔔 Notification sent: $title');
  }

  /// Handle notification tap (when user taps notification)
  void _onNotificationTapped(NotificationResponse response) {
    print('🔔 Notification tapped: ${response.payload}');
    // TODO: Navigate to specific screen or show alert details
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    print('🔔 All notifications cancelled');
  }

  /// Cancel specific notification by ID
  Future<void> cancel(int id) async {
    await _notifications.cancel(id: id);
    print('🔔 Notification $id cancelled');
  }
}
