import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Haptics
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alert_provider.dart';
import 'co_pilot_bar.dart'; // Reuse Session DTO
import '../utils/trade_signal_engine.dart';

class SuggestionCard extends ConsumerStatefulWidget {
  const SuggestionCard({super.key});

  @override
  ConsumerState<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<SuggestionCard> {
  bool _isExpanded = false;
  Timer? _updateTimer;
  
  // Smart Entry Fields
  final TextEditingController _riskController = TextEditingController(text: "50");
  double _calculatedSize = 0.0;

  // Analysis State
  String _advice = "MARKET SCANNING";
  String _reason = "Analyzing order flow...";
  Color _adviceColor = Colors.grey;
  double _pnl = 0.0;
  TradeSignal? _currentSignal;

  @override
  void initState() {
    super.initState();
    _riskController.addListener(_calculateSize);
    // Periodic update for "Real Time" feel
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _updateAdvice();
    });
  }

  void _calculateSize() {
      final risk = double.tryParse(_riskController.text) ?? 0.0;
      // Formula: Size = Risk / (StopLoss% / 100) -> Risk / 0.005
      setState(() {
          _calculatedSize = risk / 0.005; 
      });
  }

  void _updateAdvice() {
    final session = ref.read(coPilotSessionProvider);
    final currentPrice = ref.read(currentPriceProvider);
    final selectedCoin = ref.read(selectedCoinProvider);
    
    // Default Idle State (Smart Entry Mode)
    if (session == null) {
         if (currentPrice == 0) return;
         
         // REAL ANALYSIS using TradeSignalEngine
         final alertsMap = ref.read(recentAlertsProvider);
         final alerts = alertsMap[selectedCoin] ?? [];
         final signal = TradeSignalEngine.analyze(currentPrice, alerts);
         
         setState(() {
             _currentSignal = signal;
             
             // Update logic to just show trend, but specific advice comes from Calculator now
             if (signal.type == "WAIT") {
                 _advice = "SMART ENTRY READY"; // Changed for UI
                 _adviceColor = Colors.cyanAccent;
             } else {
                 _advice = "${signal.type} SETUP DETECTED";
                 _adviceColor = signal.type == "LONG" ? const Color(0xFF00FF41) : const Color(0xFFFF1493);
             }
             _reason = signal.reasoning;
         });
         
         // Ensure size is calc'd
         if (_calculatedSize == 0) _calculateSize();
         return;
    }

    // ACTIVE SESSION LOGIC
    // Calculate PnL
    double pnl = 0.0;
    if (session.side == 'LONG') {
        pnl = (currentPrice - session.entryPrice) / session.entryPrice * 100;
    } else {
        pnl = (session.entryPrice - currentPrice) / session.entryPrice * 100;
    }

    // AI Logic for Active Trade
    String newAdvice = "HOLD";
    Color newColor = const Color(0xFF00FF41);
    String newReason = "Momentum aligned";

    // 1. Exit Logic & Walls
    final alerts = ref.read(recentAlertsProvider)[session.symbol] ?? [];
    if (alerts.isNotEmpty) {
        final lastAlert = alerts.first;
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastAlert.data.timestamp;
        
        bool isOpposite = (session.side == 'LONG' && lastAlert.data.side == 'sell') || 
                          (session.side == 'SHORT' && lastAlert.data.side == 'buy');
        
        // HEAVY SELL WALL DETECTED
        if (elapsed < 10000 && isOpposite && lastAlert.data.notional > 500000) {
            newAdvice = "EXIT NOW";
            newColor = Colors.redAccent;
            newReason = "Heavy Sell Wall Detected (>${(lastAlert.data.notional/1000000).toStringAsFixed(1)}M). Suggest closing.";
            HapticFeedback.heavyImpact(); // VIBRATE
        }
    }

    // 2. Stop Loss / Profit Management
    if (pnl > 0.1 && pnl < 0.2) {
         // Fee Saver / Partial
    }
    
    // Lock Profit Trigger (Simulated Logic from backend requirements)
    if (pnl > 0.2) {
        newAdvice = "LOCK PROFIT";
        newColor = Colors.cyanAccent;
        newReason = "Profit > 0.2%. Move Stop to Entry.";
    }

    if (pnl < -0.5) {
        newAdvice = "EXIT NOW";
        newColor = Colors.red;
        newReason = "Stop Loss Hit (-0.5%)";
    } else if (pnl > 0.5) {
        newAdvice = "TRIM";
        newColor = Colors.yellow;
        newReason = "Target Reached (+0.5%)";
    }

    setState(() {
        _pnl = pnl;
        _advice = newAdvice;
        _adviceColor = newColor;
        _reason = newReason;
        _currentSignal = null; 
    });
  }

  void _showExitSummary(BuildContext context, double finalPnL) {
    double savedPercent = 0.0;
    String message = "";
    
    if (finalPnL < 0 && finalPnL > -0.5) {
        savedPercent = (-0.5 - finalPnL).abs();
        message = "The App helped you exit ${savedPercent.toStringAsFixed(2)}% higher than your standard Stop Loss.";
    } else if (finalPnL >= 0) {
        message = "Profit Secured! Great trade.";
    } else {
        message = "Stop Loss hit. Risk managed.";
    }

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF131828),
            title: const Text("Session Summary", style: TextStyle(color: Colors.white)),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text(
                        "${finalPnL > 0 ? 'gains' : 'loss'}: ${finalPnL.toStringAsFixed(2)}%", 
                        style: TextStyle(
                            color: finalPnL >= 0 ? const Color(0xFF00FF41) : Colors.red,
                            fontSize: 24, fontWeight: FontWeight.bold
                        )
                    ),
                    const SizedBox(height: 12),
                    Text(message, style: const TextStyle(color: Colors.white70)),
                ],
            ),
            actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("DONE", style: TextStyle(color: Colors.blue)),
                )
            ],
        )
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _riskController.dispose();
    super.dispose();
  }
  
  // Update Widget to show Smart Entry UI when not active
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(coPilotSessionProvider);
    final isActive = session != null;
    final selectedCoin = ref.watch(selectedCoinProvider);
    final currentPrice = ref.watch(currentPriceProvider);

    // Smart Entry Rec Price (Maker)
    double recPrice = currentPrice * 0.9999; // Long default
    double slPrice = recPrice * 0.9985;      // -0.15%
    double tpPrice = recPrice * 1.003;       // +0.3%
    
    if (_currentSignal?.type == "SHORT") {
        recPrice = currentPrice * 1.0001;
        slPrice = recPrice * 1.0015; // +0.15%
        tpPrice = recPrice * 0.997;  // -0.3%
    }
    
    // WHALE-AWARE SL ADJUSTMENT (Frontend Logic using Alerts)
    final alerts = ref.watch(recentAlertsProvider)[selectedCoin] ?? [];
    for (var alert in alerts) {
        // Look for recent Icebergs or Walls (last 30s)
        if (alert.type.contains("ICEBERG") || alert.type.contains("WALL")) {
             double wallPrice = alert.data.price;
             // If Long, Wall should be below Entry (Support). SL should be below Wall.
             if (_currentSignal?.type != "SHORT" && wallPrice < recPrice && wallPrice > (recPrice * 0.99)) {
                 slPrice = wallPrice - 5.0; // Safety Buffer
             }
             // If Short, Wall should be above Entry (Resistance). SL should be above Wall.
             if (_currentSignal?.type == "SHORT" && wallPrice > recPrice && wallPrice < (recPrice * 1.01)) {
                 slPrice = wallPrice + 5.0;
             }
        }
    }
    
    // R/R Calculation
    double potentialLoss = (recPrice - slPrice).abs();
    double potentialGain = (tpPrice - recPrice).abs();
    double rrRatio = potentialLoss == 0 ? 0 : potentialGain / potentialLoss;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF131828), // Dark card status color
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? _adviceColor : _adviceColor.withOpacity(0.5), 
          width: isActive ? 1.5 : 1
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // HEADER (Always Visible)
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Icon Status
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _adviceColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _adviceColor.withOpacity(0.5), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Text Status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isActive ? 'CO-PILOT ACTIVE' : 'SMART ENTRY',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _advice,
                          style: TextStyle(
                            color: _adviceColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // PROGRESS BAR (Active Trade Only)
          if (isActive)
             Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                 child: ClipRRect(
                     borderRadius: BorderRadius.circular(4),
                     child: LinearProgressIndicator(
                         value: (_pnl + 0.5) / 1.0, 
                         backgroundColor: Colors.red.withOpacity(0.3),
                         valueColor: AlwaysStoppedAnimation<Color>(
                             _pnl >= 0 ? const Color(0xFF00FF41) : Colors.orange
                         ),
                         minHeight: 4,
                     ),
                 ),
             ),

          // EXPANDED CONTENT
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12), // Adjusted padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.white.withOpacity(0.05)),
                  
                  // Active: Show Reason. Idle: Show Smart Entry Form.
                  if (isActive) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _reason,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ),
                          Container(
                             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                             decoration: BoxDecoration(
                                 color: Colors.green.withOpacity(0.2),
                                 borderRadius: BorderRadius.circular(4),
                                 border: Border.all(color: Colors.green.withOpacity(0.5))
                             ),
                             child: const Text(
                                 "R:R 2.0 [SNIPER]",
                                 style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                             )
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Lock Profit Button
                      if (_advice == "LOCK PROFIT")
                          ElevatedButton.icon(
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                             onPressed: () {}, // Can't act on public exchange, but visual cue
                             icon: const Icon(Icons.lock, size: 16),
                             label: const Text("LOCK PROFIT (MOVE STOP)"),
                          ),
                  ] else ...[
                      // SMART ENTRY FORM
                       Row(
                           children: [
                               Expanded(
                                   child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                           const Text("MAX LOSS (\$)", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                           SizedBox(
                                               height: 40,
                                               child: TextField(
                                                   controller: _riskController,
                                                   keyboardType: TextInputType.number,
                                                   style: const TextStyle(color: Colors.white, fontSize: 14),
                                                   decoration: const InputDecoration(
                                                       border: InputBorder.none,
                                                       hintText: "50",
                                                       hintStyle: TextStyle(color: Colors.white24)
                                                   ),
                                               ),
                                           ),
                                       ],
                                   ),
                               ),
                               Expanded(
                                   child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.end,
                                       children: [
                                           const Text("POSITION SIZE", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                           Text(
                                              "\$${_calculatedSize.toStringAsFixed(0)}",
                                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                           ),
                                       ],
                                   ),
                               ),
                           ],
                       ),
                       const SizedBox(height: 12),
                       
                       // ENTRY ROW
                       Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                               const Text("REC. ENTRY:", style: TextStyle(color: Colors.grey, fontSize: 11)),
                               Text(
                                   _formatPrice(recPrice),
                                   style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                               ),
                           ],
                       ),
                       const SizedBox(height: 8),
                       
                       // SL / TP / RR ROW
                       Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                               _buildSmallStat("STOP LOSS", slPrice, color: Colors.redAccent),
                               _buildSmallStat("TAKE PROFIT", tpPrice, color: const Color(0xFF00FF41)),
                               
                               // R/R Pill
                               Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                   decoration: BoxDecoration(
                                       color: Colors.green.withOpacity(0.2),
                                       borderRadius: BorderRadius.circular(8),
                                       border: Border.all(color: Colors.green.withOpacity(0.5))
                                   ),
                                   child: Text(
                                       "R/R ${rrRatio.toStringAsFixed(1)}",
                                       style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                   )
                               )
                           ],
                       ),

                       if (_currentSignal != null && _currentSignal!.type != "WAIT")
                           Padding(
                               padding: const EdgeInsets.only(top: 8),
                               child: Text("Whale Advice: Used Maker logic. ${_currentSignal!.reasoning}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                           ),
                  ],

                  const SizedBox(height: 12),
                  
                  // Action Buttons
                  Row(
                    children: [
                      if (!isActive)
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _adviceColor == Colors.grey ? Colors.blueGrey : _adviceColor,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () {
                                // Start Session
                                ref.read(coPilotSessionProvider.notifier).state = CoPilotSession(
                                    symbol: selectedCoin,
                                    side: _currentSignal?.type ?? "LONG", 
                                    entryPrice: recPrice, // Use Rec Price
                                    startTime: DateTime.now().millisecondsSinceEpoch,
                                    stopLoss: slPrice,
                                    takeProfit: tpPrice,
                                );
                                setState(() {
                                    _isExpanded = true; 
                                });
                            },
                            icon: const Icon(Icons.rocket_launch, size: 16),
                            label: const Text("I'M IN"),
                          ),
                        ),
                      
                      if (isActive)
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                                double closingPnL = _pnl;
                                ref.read(coPilotSessionProvider.notifier).state = null;
                                _showExitSummary(context, closingPnL);
                            },
                            icon: const Icon(Icons.stop, size: 16),
                            label: const Text("I'M OUT"),
                          ),
                        ),
                    ],
                  )
                ],
              ),
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSmallStat(String label, double value, {Color color = Colors.white}) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9)),
              Text(
                  _formatPrice(value),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)
              ),
          ],
      );
  }

  Widget _buildStatItem(String label, double value, {Color color = Colors.white}) {
      return Column(
          children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              Text(
                  _formatPrice(value),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)
              ),
          ],
      );
  }

  String _formatPrice(double price) {
    if (price < 1.0) return '\$${price.toStringAsFixed(6)}';
    if (price < 10.0) return '\$${price.toStringAsFixed(4)}';
    return '\$${price.toStringAsFixed(2)}';
  }
}
