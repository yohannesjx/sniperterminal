import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_settings.dart';

// Notification Settings Provider
final notificationSettingsProvider = StateProvider<NotificationSettings>((ref) {
  return const NotificationSettings();
});

// Previous Confidence Score Provider (for trend flip detection)
final previousConfidenceProvider = StateProvider<int>((ref) => 50);

// Spoof Counter Provider (for cluster detection)
final spoofCounterProvider = StateProvider<int>((ref) => 0);
