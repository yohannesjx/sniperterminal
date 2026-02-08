import 'package:ntp/ntp.dart';

class TimeSyncService {
  static Future<int> checkTimeOffset() async {
    try {
      DateTime ntpTime = await NTP.now();
      DateTime deviceTime = DateTime.now();
      
      int offset = ntpTime.difference(deviceTime).inMilliseconds.abs();
      return offset;
    } catch (e) {
      print("⚠️ NTP Check Failed: $e");
      return -1; // Error
    }
  }

  static Future<bool> isSynced({int thresholdMs = 1000}) async {
    int offset = await checkTimeOffset();
    if (offset == -1) return true; // Assume synced if check fails to avoid blocking (Soft Fail)
    return offset < thresholdMs;
  }
}
