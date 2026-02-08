import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Mute State Provider (Smart Mute: Time-based)
// State is DateTime? (null = unmuted, Date = muted until)
final mutedProvider = StateNotifierProvider<MuteNotifier, DateTime?>((ref) => MuteNotifier());

class MuteNotifier extends StateNotifier<DateTime?> {
  MuteNotifier() : super(null);

  // Helper check (can be used if reading notifier directly)
  bool get isMuted => state != null && DateTime.now().isBefore(state!);

  void muteFor(Duration duration) {
    state = DateTime.now().add(duration);
  }

  void unmute() {
    state = null;
  }
}

class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  factory SoundManager() => _instance;
  SoundManager._internal();

  final FlutterTts _flutterTts = FlutterTts();
  DateTime _lastSpoken = DateTime.now().subtract(const Duration(minutes: 1));
  
  // Store ref for mute checking
  WidgetRef? _ref;
  
  void setRef(WidgetRef ref) {
    _ref = ref;
  }

  Future<void> init() async {
    // 1. Platform-Specific Tuning
    if (Platform.isIOS) {
      await _flutterTts.setSpeechRate(0.5); // iOS AVSpeechSynthesizer is fast
      await _flutterTts.setPitch(1.0);
    } else {
      await _flutterTts.setSpeechRate(0.8); // Android engines are usually slower
      await _flutterTts.setPitch(0.9);      // Slightly deeper for authority
    }
    
    // 2. Voice Selection (Try for active/enhanced voices)
    await _flutterTts.setLanguage("en-US");

    // Initialize vibration capabilities check
    bool? hasVibrator = await Vibration.hasVibrator();
    print('🔊 SoundManager Initialized. Haptics: $hasVibrator');
  }

  // Helper: Military Brevity Speech Formatter
  String humanizeForSpeech(String text) {
    // 1. Remove ALL emojis and special symbols (keep only alphanumeric, $, ., space, comma)
    String clean = text.replaceAll(RegExp(r'[^\w\s\$\.,]'), '');

    // 2. Ticker Shortening (Military Call Signs)
    clean = clean.replaceAll('BTC', 'Bitcoin');
    clean = clean.replaceAll('ETH', 'Ether');
    clean = clean.replaceAll('SOL', 'Sol');
    clean = clean.replaceAll('USDT', ''); // Drop USDT entirely
    
    // 3. AGGRESSIVE NUMBER FORMATTING (Military Brevity)
    // Match dollar amounts with optional commas and decimals: $154,008.50 or $2540000
    clean = clean.replaceAllMapped(
      RegExp(r'\$([0-9,]+(?:\.\d+)?)'), 
      (Match m) {
        // Remove commas and parse as double
        String numStr = m[1]!.replaceAll(',', '');
        double value = double.tryParse(numStr) ?? 0;
        
        // Aggressive Rounding: Strip decimals for values > $10
        if (value > 10) {
          value = value.roundToDouble();
        }
        
        // Format based on magnitude
        if (value >= 1000000) {
          // 1M+: "2.5 Million"
          double millions = value / 1000000;
          return '${millions.toStringAsFixed(1)} Million';
        } else if (value >= 10000) {
          // 10K-999K: "154 K"
          int thousands = (value / 1000).round();
          return '$thousands K';
        } else {
          // < 10K: Just the number
          return value.toStringAsFixed(0);
        }
      }
    );
    
    // 4. Clean up "point 0" artifacts (e.g., "2.0 Million" -> "2 Million")
    clean = clean.replaceAll(RegExp(r'(\d+)\.0\s'), r'$1 ');
    
    // 5. Add breath pauses (periods create natural breaks)
    clean = clean.replaceAll('\n', '. ');
    clean = clean.replaceAll(':', '.');
    
    // 6. Collapse multiple spaces
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return clean;
  }

  Future<void> playWhaleAlert(double value) async {
    if (value >= 1000000) { 
       if (await Vibration.hasVibrator() ?? false) {
         Vibration.vibrate(duration: 500); 
       }
    }
  }

  Future<void> playSpoofAlert() async {
    if (_shouldThrottle()) return;
    
    await speak("Spoof Detected");
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 200, 100, 200]); 
    }
  }

  Future<void> playWallAlert() async {
     if (_shouldThrottle()) return;

     await speak("Massive Wall Detected");
     if (await Vibration.hasVibrator() ?? false) {
       Vibration.vibrate(duration: 1000); 
     }
  }
  
  Future<void> playGodTierAlert() async {
    if (_shouldThrottle()) return;

    await speak("God Tier Alert");
    if (await Vibration.hasVibrator() ?? false) {
       Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 1000]); 
    }
  }

  // Public wrapper to speak with humanization and mute check
  Future<void> speak(String text) async {
    // Check mute state
    if (_ref != null) {
      final muteUntil = _ref!.read(mutedProvider);
      final isMuted = muteUntil != null && DateTime.now().isBefore(muteUntil);
      
      if (isMuted) {
        print('🔇 Sound muted, skipping: $text');
        return;
      }
    }
    
    String narrative = humanizeForSpeech(text);
    await _flutterTts.speak(narrative);
    _lastSpoken = DateTime.now();
  }

  Future<void> _speak(String text) async {
      await speak(text); // Redirect to main
  }

  bool _shouldThrottle() {
    // Throttle: Max 1 spoken alert per 5 seconds
    // Note: Market Narrator might call speak directly, bypassing this if it wants
    if (DateTime.now().difference(_lastSpoken).inSeconds < 5) {
      return true;
    }
    return false;
  }
}
