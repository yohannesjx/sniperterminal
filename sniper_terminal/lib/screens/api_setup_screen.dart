import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sniper_terminal/services/order_signer.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/screens/dashboard.dart';
import 'package:sniper_terminal/screens/qr_scanner_screen.dart';

class ApiSetupScreen extends StatefulWidget {
  const ApiSetupScreen({super.key});

  @override
  State<ApiSetupScreen> createState() => _ApiSetupScreenState();
}

class _ApiSetupScreenState extends State<ApiSetupScreen> with SingleTickerProviderStateMixin {
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _orderSigner = OrderSigner();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  bool _isTestnet = true; // Default to Demo
  
  // Separate storage for UI state (to persist text when switching)
  String _testnetApiKey = '';
  String _testnetSecretKey = '';
  String _prodApiKey = '';
  String _prodSecretKey = '';

  bool _isValidating = false;
  bool _enableBiometrics = false;
  bool _biometricsAvailable = false;
  
  late AnimationController _successAnimationController;
  late Animation<double> _successScaleAnimation;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadKeys(); 
    
    // Ensure OrderSigner matches default Demo mode
    _orderSigner.setEnvironment(true); 
    
    _successAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }
  
  // Load ALL keys into local state
  Future<void> _loadKeys() async {
    _testnetApiKey = await _storage.read(key: 'testnet_binance_api_key') ?? '';
    _testnetSecretKey = await _storage.read(key: 'testnet_binance_secret_key') ?? '';
    _prodApiKey = await _storage.read(key: 'prod_binance_api_key') ?? '';
    _prodSecretKey = await _storage.read(key: 'prod_binance_secret_key') ?? '';
    
    // Initial populate based on default mode (Testnet)
    _updateControllers();
  }

  void _updateControllers() {
    if (_isTestnet) {
      _apiKeyController.text = _testnetApiKey;
      _secretKeyController.text = _testnetSecretKey;
    } else {
      _apiKeyController.text = _prodApiKey;
      _secretKeyController.text = _prodSecretKey;
    }
  }

  Future<void> _toggleEnvironment(bool value) async {
    // 1. Save current input to local state before switching
    if (_isTestnet) {
      _testnetApiKey = _apiKeyController.text;
      _testnetSecretKey = _secretKeyController.text;
    } else {
      _prodApiKey = _apiKeyController.text;
      _prodSecretKey = _secretKeyController.text;
    }

    // 2. Switch Mode
    setState(() {
      _isTestnet = value;
    });
    
    // 3. Update Backend Environment
    await _orderSigner.setEnvironment(_isTestnet);
    
    // 4. Update UI with new mode's keys
    _updateControllers();
  }

  Future<void> _loadEnvironment() async {
     // No-op: We control environment locally and push to OrderSigner
  }

  Future<void> _pasteFromClipboard(TextEditingController controller) async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      controller.text = clipboardData.text!;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📋 Pasted from clipboard')),
        );
      }
    }
  }

  Future<void> _scanQRCode() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScannerScreen(
          onScanned: (data) {
            bool success = false;
            try {
              // 1. Try JSON Format: {"apiKey": "...", "secretKey": "..."}
              if (data.trim().startsWith('{')) {
                final jsonMap = json.decode(data);
                if (jsonMap is Map) {
                   final key = jsonMap['apiKey'] ?? jsonMap['APIKey'];
                   final secret = jsonMap['secretKey'] ?? jsonMap['SecretKey'];
                   
                   if (key != null && secret != null) {
                      _apiKeyController.text = key.toString();
                      _secretKeyController.text = secret.toString();
                      success = true;
                   }
                }
              }
            } catch (e) {
              // JSON parse failed, try other formats
            }

            if (!success) {
                // 2. Try Legacy Format: "apiKey:secretKey"
                if (data.contains(':') && !data.contains('{')) {
                  final parts = data.split(':');
                  if (parts.length >= 2) {
                    _apiKeyController.text = parts[0].trim();
                    _secretKeyController.text = parts[1].trim();
                    success = true;
                  }
                } else {
                  // 3. Fallback: Entire string as API Key
                  _apiKeyController.text = data.trim();
                  success = true; // Partial success
                }
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(success ? '✅ QR Code Parsed' : '⚠️ Format Not Recognized')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _checkBiometrics() async {
    try {
      final available = await _localAuth.canCheckBiometrics;
      setState(() {
        _biometricsAvailable = available;
      });
    } catch (e) {
      setState(() {
        _biometricsAvailable = false;
      });
    }
  }



  Future<void> _validateAndSave() async {
    // Save current input to state before saving to disk
    if (_isTestnet) {
      _testnetApiKey = _apiKeyController.text.trim();
      _testnetSecretKey = _secretKeyController.text.trim();
    } else {
      _prodApiKey = _apiKeyController.text.trim();
      _prodSecretKey = _secretKeyController.text.trim();
    }

    if (_apiKeyController.text.trim().isEmpty || _secretKeyController.text.trim().isEmpty) {
      _showError('Please enter both API Key and Secret Key');
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      // 1. Save keys temporarily
      await _orderSigner.saveKeys(
        _apiKeyController.text.trim(),
        _secretKeyController.text.trim(),
      );

      // 2. Pre-Flight Permission Check
      final result = await _orderSigner.checkPermissions();

      if (result.contains('✅')) {
        // SUCCESS: Keys are valid (Futures check handled in OrderSigner message)
        await _showSuccessAnimation();
        
        // 3. Optional Biometric Setup
        if (_biometricsAvailable && _enableBiometrics) {
          try {
             // 5-second timeout to prevent indefinite hang
             await _setupBiometrics().timeout(const Duration(seconds: 5));
          } catch (e) {
             print('Biometrics setup skipped or timed out: $e');
          }
        }
        
        // 4. Navigate to Dashboard
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      } else {
        // FAILURE: Parse specific error
        _handlePermissionError(result);
      }
    } catch (e) {
      _handlePermissionError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  void _handlePermissionError(String error) {
    String message = 'Authentication failed';
    
    if (error.contains('-2015')) {
      message = '❌ Error -2015: Invalid API Key\n\nDid you forget to:\n• Whitelist your IP on Binance?\n• Enable "Futures" trading permissions?';
    } else if (error.contains('-2014')) {
      message = '❌ Error -2014: Invalid API Key Format\n\nPlease check your API key for typos.';
    } else if (error.contains('-1021')) {
      message = '❌ Error -1021: Timestamp Desync\n\nYour device clock is out of sync. Please enable automatic time in Settings.';
    } else if (!error.contains('Futures')) {
      // message = '⚠️ Futures Trading Not Enabled\n\nPlease enable "Futures" permission in your Binance API settings.';
       // OrderSigner already checks specifics, pass raw error if generic
       if (error.contains('Connected')) {
          // Success message treated as error? No, checkPermissions returns string
          // logic above handles success.
       } else {
          message = error;
       }
    } else {
       message = error;
    }
    
    _showError(message);
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(
              'VALIDATION FAILED',
              style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.roboto(color: Colors.white, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.orbitron(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuccessAnimation() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ScaleTransition(
        scale: _successScaleAnimation,
        child: AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.greenAccent, width: 2),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                'TERMINAL ARMED',
                style: GoogleFonts.orbitron(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'API Keys Validated\nFutures Trading Enabled',
                style: GoogleFonts.roboto(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    
    _successAnimationController.forward();
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> _setupBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Enable biometric protection for trade execution',
      );
      
      if (authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🔒 Biometric Lock Enabled')),
          );
        }
      }
    } catch (e) {
      // Biometric setup failed, continue anyway
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    _successAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _isTestnet ? Colors.cyanAccent : Colors.amber;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'API SETUP',
          style: GoogleFonts.orbitron(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Environment Toggle
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: themeColor.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(10),
                color: themeColor.withOpacity(0.1),
              ),
              child: SwitchListTile(
                title: Text(
                  _isTestnet ? 'TESTNET MODE' : 'PRODUCTION MODE',
                  style: GoogleFonts.orbitron(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  _isTestnet ? 'Risk-Free Testing' : 'Real Money Trading',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                value: _isTestnet,
                activeColor: Colors.cyanAccent,
                inactiveThumbColor: Colors.amber,
                onChanged: (value) async {
                  await _toggleEnvironment(value);
                },
              ),
            ),
            
            const SizedBox(height: 30),
            
            // API Key Field - Animated Switcher not strictly required if we just swap text quickly, 
            // but we can wrap it for effect. Using simpler replacement for now to fix logic first.
            Text(
              'API KEY',
              style: GoogleFonts.orbitron(
                color: Colors.greenAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKeyController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter your Binance API Key',
                hintStyle: TextStyle(color: Colors.grey[600]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste, color: Colors.greenAccent),
                  onPressed: () => _pasteFromClipboard(_apiKeyController),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Secret Key Field
            Text(
              'SECRET KEY',
              style: GoogleFonts.orbitron(
                color: Colors.greenAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secretKeyController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter your Binance Secret Key',
                hintStyle: TextStyle(color: Colors.grey[600]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.greenAccent),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste, color: Colors.greenAccent),
                  onPressed: () => _pasteFromClipboard(_secretKeyController),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // QR Scanner Button (Rest of UI)

            OutlinedButton.icon(
              onPressed: _scanQRCode,
              icon: const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent),
              label: Text(
                'SCAN QR CODE',
                style: GoogleFonts.orbitron(color: Colors.cyanAccent),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.cyanAccent),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Biometric Lock Option
            if (_biometricsAvailable)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[800]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fingerprint, color: Colors.greenAccent, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Biometric Lock',
                            style: GoogleFonts.orbitron(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Require FaceID/Fingerprint before executing trades',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _enableBiometrics,
                      activeColor: Colors.greenAccent,
                      onChanged: (value) {
                        setState(() {
                          _enableBiometrics = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 30),
            
            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Only enable "Spot" and "Futures" trading permissions. NEVER enable "Withdrawals" or "Universal Transfer".',
                      style: GoogleFonts.roboto(
                        color: Colors.amber[200],
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Save & Validate Button
            ElevatedButton(
              onPressed: _isValidating ? null : _validateAndSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isValidating
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : Text(
                      'SAVE & VALIDATE KEYS',
                      style: GoogleFonts.orbitron(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


