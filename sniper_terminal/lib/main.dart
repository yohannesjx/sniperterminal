import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/screens/dashboard.dart';
import 'package:sniper_terminal/screens/settings.dart';
import 'package:sniper_terminal/screens/signup.dart';
import 'package:sniper_terminal/screens/onboarding_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print("⚠️ DefaultFirebaseOptions not found or failed. Trying manual init...");
    await Firebase.initializeApp(
      name: 'sniper-terminal',
      options: const FirebaseOptions(
        apiKey: 'AIzaSyBG98-rZtXgw8YKf1W6IgleqqWQLhkjfMc',
        appId: '1:971965790876:ios:69ed00e604aa2ac7ed8b59', // Using iOS App ID as fallback
        messagingSenderId: '971965790876',
        projectId: 'scanner-984c7',
        storageBucket: 'scanner-984c7.firebasestorage.app',
      ),
    );
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SniperState()),
      ],
      child: const SniperTerminalApp(),
    ),
  );
}

class SniperTerminalApp extends StatelessWidget {
  const SniperTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sniper Terminal',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.orbitronTextTheme(
          Theme.of(context).textTheme,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const SplashScreen(),
      routes: {
        '/settings': (context) => const SettingsScreen(),
        '/signup': (context) => const SignupScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}

// Splash Screen to check onboarding status
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    // Small delay for splash effect
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Check for ANY valid setup (Prod or Testnet)
    final prodKey = await _storage.read(key: 'prod_binance_api_key');
    final testKey = await _storage.read(key: 'testnet_binance_api_key');
    final hasCompletedSetup = (prodKey != null && prodKey.isNotEmpty) || (testKey != null && testKey.isNotEmpty);
    
    if (!mounted) return;
    
    if (hasCompletedSetup) {
      // User has completed setup, go to dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      // New user, show onboarding
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SNIPER TERMINAL',
              style: GoogleFonts.orbitron(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.greenAccent,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ],
        ),
      ),
    );
  }
}
