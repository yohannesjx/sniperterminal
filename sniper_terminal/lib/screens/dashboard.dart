import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/widgets/coin_selector.dart';
import 'package:sniper_terminal/widgets/sonar_display.dart';
import 'package:sniper_terminal/widgets/sniper_card.dart';
import 'package:sniper_terminal/widgets/live_sniper_hud.dart';

import 'package:sniper_terminal/services/permission_checker.dart';
import 'package:sniper_terminal/services/order_signer.dart';
import 'package:sniper_terminal/services/websocket_service.dart';
import 'package:sniper_terminal/widgets/system_health_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibration/vibration.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _webSocketService = WebSocketService();
  final _orderSigner = OrderSigner();
  // Signal? _currentSignal; // MOVED TO PROVIDER

  @override
  void initState() {
    super.initState();
    _webSocketService.connect();
    _orderSigner.fetchExchangeInfo(); // LOAD PRECISION FILTERS
    _webSocketService.signalStream.listen((signal) {
      if (!mounted) return;
      
      // Add to Provider & Trigger Vibration if necessary
      Provider.of<SniperState>(context, listen: false).addSignal(signal);

      if (signal.tier == "1" || signal.score > 9.0) {
        try { Vibration.vibrate(duration: 500); } catch (_) {}
      }
    });

    // Start Monitoring for Existing Positions on Load
    // (Ensure we catch any existing opens on startup)
    WidgetsBinding.instance.addPostFrameCallback((_) {
       Provider.of<SniperState>(context, listen: false).refreshPositions();
    });
  }

  @override
  void dispose() {
    // We don't dispose the singleton service here as it might be used elsewhere
    // But we should cancel the subscription if we stored it (we didn't store it in a variable here which is a minor leak if we push/pop)
    // For now, consistent with previous code.
    super.dispose();
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('SNIPER TERMINAL', style: GoogleFonts.orbitron(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // Sensitivity Check
            if (details.primaryVelocity == null) return;
            
            // Swipe Left (Next Coin)
            if (details.primaryVelocity! < -500) { // Negative velocity = Left
               Provider.of<SniperState>(context, listen: false).selectNextCoin();
               try { Vibration.vibrate(duration: 50); } catch (_) {}
            }
            
            // Swipe Right (Prev Coin)
            if (details.primaryVelocity! > 500) { // Positive velocity = Right
               Provider.of<SniperState>(context, listen: false).selectPreviousCoin();
               try { Vibration.vibrate(duration: 50); } catch (_) {}
            }
          },
          child: Column(
            children: [
              // System Health Bar
              Consumer<SniperState>(
                builder: (context, state, child) {
                  return SystemHealthBar(
                    status: state.healthStatus,
                    onTap: () {
                      if (!state.isSystemHealthy) {
                        _showSystemOfflineDialog(context, state);
                      }
                    },
                  );
                },
              ),
              
              // 1. Asset Selector
              const CoinSelector(),
              
              // 2. Submarine Sonar
              const Expanded(
                flex: 2,
                child: SonarDisplay(),
              ),

              // 3. Dynamic Card Area (Sniper Signal OR Live Position)
              Expanded(
                flex: 5,
                child: Consumer<SniperState>(
                    builder: (context, state, child) {
                        // 3. LIVE POSITION HUD (Replaces Card)
                        if (state.activePosition != null) {
                          return Column(
                            children: [
                              const Expanded(child: LiveSniperHUD()),
                              // QUICK TARGET TOGGLE
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildTargetButton(context, state, 2.0),
                                    _buildTargetButton(context, state, 5.0),
                                    _buildTargetButton(context, state, 10.0),
                                  ],
                                ),
                              ),
                            ],
                          );
                        } else {
                          return SniperCard(
                            onExecute: () {
                              // Safety Lock: Check system health before execution
                              if (!state.isSystemHealthy) {
                                _showSystemOfflineDialog(context, state);
                                return;
                              }
                              
                              if (state.activeSignal != null) {
                                PermissionChecker.check(context, onGranted: () {
                                  state.executeSafeTrade(
                                    side: state.activeSignal!.side == "LONG" ? "BUY" : "SELL",
                                    onSuccess: () {
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚀 Order Executed!')));
                                    },
                                    onError: (err) {
                                      if (mounted)  {
                                        try { Vibration.vibrate(duration: 500); } catch (_) {}
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                                      }
                                    }
                                  );
                                });
                              }
                            },
                          );
                        }
                    }
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetButton(BuildContext context, SniperState state, double amount) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[900],
        side: const BorderSide(color: Colors.greenAccent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        state.setQuickTarget(amount);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🎯 Target Set: +\$$amount')));
        try { Vibration.vibrate(duration: 50); } catch (_) {}
      },
      child: Text(
        '+\$${amount.toStringAsFixed(0)}',
        style: GoogleFonts.orbitron(color: Colors.greenAccent, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showSystemOfflineDialog(BuildContext context, SniperState state) {
    final failures = <String>[];
    
    if (!state.healthStatus.scannerHubConnected) {
      failures.add('Scanner Hub offline (Backend unreachable)');
    }
    if (!state.healthStatus.exchangeApiHealthy) {
      failures.add('Exchange API unavailable (Binance unreachable)');
    }
    if (!state.healthStatus.authStateValid) {
      failures.add('Auth State invalid (Check API keys in Settings)');
    }
    if (!state.healthStatus.timeSyncHealthy) {
      failures.add('Time Sync failed (Device clock out of sync)');
    }
    
    final failureReason = failures.isEmpty ? 'All systems operational' : failures.join('\n');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(
              'SYSTEM OFFLINE',
              style: GoogleFonts.orbitron(color: Colors.redAccent, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trading is disabled due to system health issues:',
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              failureReason,
              style: GoogleFonts.robotoMono(
                color: Colors.redAccent,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
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
}
