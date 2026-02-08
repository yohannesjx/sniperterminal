import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/notification_service.dart';

/// Top-level background handler for FCM
/// Must be outside the class to be called when app is terminated
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background handling
  await Firebase.initializeApp();
  print("🌙 Background FCM Message: ${message.messageId}");
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize FCM Service
  Future<void> init() async {
    // 1. Request Permission (Critical for iOS)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ FCM Authorized');
      
      // 2. Set Background Handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 3. Foreground Message Listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📩 Foreground FCM: ${message.notification?.title}');
        
        // Show local notification banner
        if (message.notification != null) {
          NotificationService().showNotification(
            message.notification!.title ?? 'Whale Alert',
            message.notification!.body ?? 'Critical activity detected',
          );
        }
      });

      // 4. Default Subscription (can be managed by user settings later)
      // We initally subscribe, but provider logic will handle toggles
      // subscribeToWhales(); 
      // (Moved to Provider to respect persisted settings)
      
    } else {
      print('❌ FCM Permission Denied');
    }
  }

  /// Get FCM Token (for debugging/direct targeting)
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Subscribe to global Whale Alerts topic
  Future<void> subscribeToWhales() async {
    await _messaging.subscribeToTopic('ALL_WHALES');
    print('✅ Subscribed to ALL_WHALES topic');
  }

  /// Unsubscribe from global Whale Alerts topic
  Future<void> unsubscribeFromWhales() async {
    await _messaging.unsubscribeFromTopic('ALL_WHALES');
    print('🔕 Unsubscribed from ALL_WHALES topic');
  }
}
