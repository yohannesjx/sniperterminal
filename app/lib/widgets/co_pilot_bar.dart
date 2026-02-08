import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alert_provider.dart';

// State for active session
final coPilotSessionProvider = StateProvider<CoPilotSession?>((ref) => null);

class CoPilotSession {
  final String symbol;
  final String side;
  final double entryPrice;
  final int startTime;
  final double stopLoss;
  final double takeProfit;

  CoPilotSession({
    required this.symbol,
    required this.side,
    required this.entryPrice,
    required this.startTime,
    required this.stopLoss,
    required this.takeProfit,
  });
}

class CoPilotStatusBar extends ConsumerStatefulWidget {
  const CoPilotStatusBar({super.key});

  @override
  ConsumerState<CoPilotStatusBar> createState() => _CoPilotStatusBarState();
}

class _CoPilotStatusBarState extends ConsumerState<CoPilotStatusBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _updateTimer;
  
  String _advice = "ANALYZING...";
  String _reason = "Tracking Whales...";
  Color _adviceColor = Colors.grey;
  double _pnl = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Simulated Advisor Updates
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateAdvice();
    });
  }

  void _updateAdvice() {
    final session = ref.read(coPilotSessionProvider);
    if (session == null) return;

    final currentPrice = ref.read(currentPriceProvider);
    if (currentPrice == 0) return;

    // Calculate PnL
    double pnl = 0.0;
    if (session.side == 'LONG') {
        pnl = (currentPrice - session.entryPrice) / session.entryPrice * 100;
    } else {
        pnl = (session.entryPrice - currentPrice) / session.entryPrice * 100;
    }

    // AI Logic (Simulation of Backend Logic for immediate UI feedback)
    String newAdvice = "HOLD";
    Color newColor = const Color(0xFF00FF41);
    String newReason = "Strong Momentum";

    // 1. Exit Logic (Whale Dump Check - Simulated)
    // In real app, we'd listen to a provider updated by backend "Advice" signal
    // For now, let's use recent alerts locally
    final alerts = ref.read(recentAlertsProvider)[session.symbol] ?? [];
    if (alerts.isNotEmpty) {
        final lastAlert = alerts.first;
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastAlert.data.timestamp;
        
        bool isOpposite = (session.side == 'LONG' && lastAlert.data.side == 'sell') || 
                          (session.side == 'SHORT' && lastAlert.data.side == 'buy');
        
        if (elapsed < 10000 && isOpposite && lastAlert.data.notional > 500000) {
            newAdvice = "EXIT NOW";
            newColor = Colors.redAccent;
            newReason = "Opposite Whale Detected!";
        }
    }

    // 2. Stop Loss
    if (pnl < -0.5) {
        newAdvice = "EXIT NOW";
        newColor = Colors.red;
        newReason = "Stop Loss Hit (-0.5%)";
    } else if (pnl > 0.5) {
        newAdvice = "TRIM";
        newColor = Colors.yellow;
        newReason = "Target Reached (+0.5%)";
    }

    if (mounted) {
        setState(() {
            _pnl = pnl;
            _advice = newAdvice;
            _adviceColor = newColor;
            _reason = newReason;
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(coPilotSessionProvider);

    if (session != null && _controller.status == AnimationStatus.dismissed) {
        _controller.forward();
    } else if (session == null && _controller.status == AnimationStatus.completed) {
        _controller.reverse();
    }

    if (session == null && _controller.isDismissed) return const SizedBox.shrink();

    return SlideTransition(
      position: _offsetAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0d1117),
          border: Border(
            top: BorderSide(color: _adviceColor, width: 2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // PnL
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PnL',
                    style: TextStyle(color: Colors.grey[500], fontSize: 10),
                  ),
                  Text(
                    '${_pnl > 0 ? '+' : ''}${_pnl.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: _pnl >= 0 ? const Color(0xFF00FF41) : Colors.redAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Courier',
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              
              // Divider
              Container(width: 1, height: 30, color: Colors.white10),
              const SizedBox(width: 20),

              // Advice
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        children: [
                            Text(
                              "AI ADVICE: ",
                              style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _advice,
                              style: TextStyle(color: _adviceColor, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                        ]
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _reason,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Close Button
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () {
                    ref.read(coPilotSessionProvider.notifier).state = null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
