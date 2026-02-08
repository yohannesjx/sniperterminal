import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/main_screen.dart';
import 'utils/notification_service.dart';
import 'services/fcm_service.dart';
import 'providers/notification_settings_provider.dart';
import 'models/notification_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  // Expects valid google-services.json (Android) or GoogleService-Info.plist (iOS)
  await Firebase.initializeApp();
  
  // Initialize notification services
  await NotificationService().init(); // Local Notifications
  await FCMService().init();          // Remote Notifications
  
  runApp(
    const ProviderScope(
      child: WhaleRadarApp(),
    ),
  );
}

class WhaleRadarApp extends ConsumerWidget {
  const WhaleRadarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Global Listener for Notification Settings
    // Handles Opt-In/Opt-Out logic for FCM Topics
    ref.listen<NotificationSettings>(notificationSettingsProvider, (previous, next) {
      if (previous?.subscribeToWhales != next.subscribeToWhales) {
        if (next.subscribeToWhales) {
          FCMService().subscribeToWhales();
        } else {
          FCMService().unsubscribeFromWhales();
        }
      }
    });

    return MaterialApp(
      title: 'Whale Radar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0e27),
        primaryColor: const Color(0xFF00FF41),
        fontFamily: 'Courier New', // Hacker aesthetic
      ),
      home: const MainScreen(),
    );
  }
}
