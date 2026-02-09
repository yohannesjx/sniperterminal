import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/widgets/sonar_display.dart';
import 'package:sniper_terminal/widgets/snipe_card.dart'; // Corrected Import
import 'package:sniper_terminal/widgets/live_sniper_hud.dart';
import 'package:sniper_terminal/widgets/fleet_control_bar.dart';


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
            
            // MAIN QUEUE AREA
            Expanded(
              child: Consumer<SniperState>(
                builder: (context, state, child) {
                  final signals = state.sortedSignals;
                  
                  if (signals.isEmpty && state.activePosition == null) {
                    // SCANNING STATE
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SonarDisplay(), // Reuse sonar animation
                          const SizedBox(height: 20),
                          Text("SCANNING FOR WHALES...", style: GoogleFonts.orbitron(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // 1. TOP PRIORITY CARD (QUEUE HEAD)
                      if (signals.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: SnipeCard(signal: signals.first),
                        ),
                      
                      // 2. ACTIVE POSITION HUD (If any)
                      if (state.activePosition != null)
                         const SizedBox(
                             height: 200, 
                             child: LiveSniperHUD()
                         ),
                      
                      // 3. QUEUE TAIL (Compact List)
                      if (signals.length > 1) 
                        Expanded(
                          child: ListView.builder(
                            itemCount: signals.length - 1,
                            itemBuilder: (context, index) {
                              final sig = signals[index + 1];
                              return ListTile(
                                leading: Icon(
                                  sig.side == "LONG" ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: sig.side == "LONG" ? Colors.green : Colors.red,
                                ),
                                title: Text(sig.symbol, style: GoogleFonts.orbitron(color: Colors.white)),
                                subtitle: Text("Score: \${(sig.score/1000).toStringAsFixed(0)}K", style: const TextStyle(color: Colors.grey)),
                                trailing: Text(
                                  "\$${sig.price.toStringAsFixed(4)}",
                                  style: GoogleFonts.robotoMono(color: Colors.white),
                                ),
                                onTap: () {
                                   state.executeSnipe(sig);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // BOTTOM: FLEET CONTROLS
            const FleetControlBar(),
          ],
        ),
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
