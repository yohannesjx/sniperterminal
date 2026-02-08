import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sniper_terminal/services/order_signer.dart';
import 'package:sniper_terminal/services/time_sync_service.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _orderSigner = OrderSigner();

  bool _isTestnet = false;

  @override
  void initState() {
    super.initState();
    _loadEnvironmentAndKeys();
  }

  Future<void> _loadEnvironmentAndKeys() async {
    _isTestnet = await _orderSigner.isTestnet;
    await _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keys = await _orderSigner.getKeys();
    setState(() {
      _apiKeyController.text = keys['apiKey'] ?? '';
      _secretKeyController.text = keys['secretKey'] ?? '';
    });
  }

  Future<void> _toggleEnvironment(bool value) async {
    await _orderSigner.setEnvironment(value);
    setState(() {
      _isTestnet = value;
    });
    await _loadKeys(); // Reload keys for the new environment
  }

import 'package:sniper_terminal/screens/qr_scanner_screen.dart';
import 'dart:convert';

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
                      setState(() {
                        _apiKeyController.text = key.toString();
                        _secretKeyController.text = secret.toString();
                      });
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
                    setState(() {
                      _apiKeyController.text = parts[0].trim();
                      _secretKeyController.text = parts[1].trim();
                    });
                    success = true;
                  }
                } else {
                  // 3. Fallback: Entire string as API Key
                  setState(() {
                     _apiKeyController.text = data.trim();
                  });
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

  Future<void> _checkPermissions() async {
      // Temporarily save first to ensure we check current inputs
      await _orderSigner.saveKeys(_apiKeyController.text.trim(), _secretKeyController.text.trim());
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checking Permissions...')));
      
      final result = await _orderSigner.checkPermissions();
      
      if (!mounted) return;
      showDialog(
          context: context, 
          builder: (context) => AlertDialog(
              title: const Text('API Permissions'),
              content: SingleChildScrollView(child: Text(result)),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          )
      );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _isTestnet ? Colors.cyanAccent : Colors.amber;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('SETTINGS', style: GoogleFonts.orbitron(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
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
                    style: GoogleFonts.orbitron(color: themeColor, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _isTestnet ? 'Using Testnet (Risk Free)' : 'Using Real Money (Be Careful!)',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  value: _isTestnet,
                  activeColor: Colors.cyanAccent,
                  inactiveThumbColor: Colors.amber,
                  inactiveTrackColor: Colors.amber.withOpacity(0.3),
                  onChanged: _toggleEnvironment,
                ),
              ),
              const SizedBox(height: 30),

              Text(
                'BINANCE API CREDENTIALS',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: 'API Key (${_isTestnet ? "Testnet" : "Prod"})',
                  labelStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _secretKeyController,
                decoration: InputDecoration(
                  labelText: 'Secret Key (${_isTestnet ? "Testnet" : "Prod"})',
                  labelStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                ),
                style: const TextStyle(color: Colors.white),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              
              // QR Scanner Button
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
              ElevatedButton(
                onPressed: () async {
                    // Trim keys to avoid copy-paste errors
                    await _orderSigner.saveKeys(
                        _apiKeyController.text.trim(), 
                        _secretKeyController.text.trim()
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ ${_isTestnet ? "Testnet" : "Production"} Keys Saved!')),
                    );
                    // Don't pop, let them execute check permissions
                },
                style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
                child: Text('SAVE KEYS', style: GoogleFonts.orbitron(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              const Text(
                '⚠️ Ensure "Futures Trading" is enabled and your IP is whitelisted on Binance.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _checkPermissions,
                icon: const Icon(Icons.shield_outlined, color: Colors.black),
                label: Text('CHECK PERMISSIONS', style: GoogleFonts.orbitron(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              ),
              const SizedBox(height: 50),

              
              Text(
                'PROFIT TAKING',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Consumer<SniperState>(
                builder: (context, state, child) {
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Auto-Close At:', style: TextStyle(color: Colors.grey[400])),
                          Text(
                            '\$${state.targetProfit.toStringAsFixed(0)}',
                            style: GoogleFonts.orbitron(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ],
                      ),
                      Slider(
                        value: state.targetProfit,
                        min: 10,
                        max: 500,
                        divisions: 49,
                        activeColor: Colors.greenAccent,
                        inactiveColor: Colors.grey[800],
                        onChanged: (val) => state.setTargetProfit(val),
                      ),
                      Text(
                        'Automatically close trade if unrealized profit reaches this amount.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 30),

              Text(
                'SYSTEM & SECURITY',
                style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 18),
              ),
              const SizedBox(height: 10),
              
              // TIME SYNC CHECK
              ElevatedButton.icon(
                onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏳ Checking NTP Server...')));
                    int offset = await TimeSyncService.checkTimeOffset();
                    if (!context.mounted) return;
                    
                    if (offset == -1) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Time Sync Check Failed (Network Error)')));
                    } else if (offset > 1000) {
                         showDialog(
                             context: context, 
                             builder: (context) => AlertDialog(
                                 title: const Text('⚠️ CLOCK DESYNC'),
                                 content: Text('Your device is off by ${offset}ms! Trading may fail (Error -1021). Please sync your phone clock.'),
                                 actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                             )
                         );
                    } else {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ System Clock Synced (Offset: ${offset}ms)')));
                    }
                },
                icon: const Icon(Icons.access_time, color: Colors.white),
                label: Text('CHECK TIME SYNC', style: GoogleFonts.orbitron(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
              ),
              
              const SizedBox(height: 20),

              // BURN TERMINAL
              ElevatedButton.icon(
                onPressed: () {
                    showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                            title: const Text('🔥 BURN TERMINAL?'),
                            content: const Text('This will wipe all API Keys, Logs, and Settings immediately. Action is irreversible.'),
                            actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                                TextButton(
                                    onPressed: () async {
                                        Navigator.pop(context);
                                        await Provider.of<SniperState>(context, listen: false).clearAllData();
                                        if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('💥 Terminal Burned. Data Wiped.')));
                                            // Optionally restart app or nav to home
                                            Navigator.pop(context); 
                                        }
                                    }, 
                                    child: const Text('BURN IT', style: TextStyle(color: Colors.red))
                                ),
                            ],
                        )
                    );
                },
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                label: Text('BURN TERMINAL (WIPE DATA)', style: GoogleFonts.orbitron(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
              
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
