import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/models/signal.dart';
import 'package:sniper_terminal/widgets/entry_gauge.dart';

class SniperCard extends StatefulWidget {
  final VoidCallback onExecute;

  const SniperCard({super.key, required this.onExecute});

  @override
  State<SniperCard> createState() => _SniperCardState();
}

class _SniperCardState extends State<SniperCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _timer;
  String _timeAgo = "Just now";
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    // Pulse Animation for Safe Entry Button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ticker for Signal Age
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateTimeAgo();
        });
      }
    });
  }

  void _updateTimeAgo() {
    final state = Provider.of<SniperState>(context, listen: false);
    final signal = state.activeSignal;
    if (signal != null) {
      final diff = DateTime.now().millisecondsSinceEpoch - signal.timestamp;
      final seconds = (diff / 1000).floor();
      
      if (seconds > 60) {
        _timeAgo = "EXPIRED (${seconds}s)";
        _isExpired = true;
      } else {
        _timeAgo = "${seconds}s ago";
        _isExpired = false;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }
  
  // Logic: 100% = Perfect. 0% = bad.
  // Factors: 
  // 1. Time decay (0-60s)
  // 2. Price deviation (0.00% to 0.22%)
  double _calculateEntryScore(Signal signal) {
    // 1. Price Deviation (Simulated as we don't have live price separate from signal price yet)
    // Assuming signal.price is "Signal Entry" and we simulate current price is same for now
    // In real app, compare `currentTickerPrice` vs `signal.price`.
    double deviationPct = 0.0; // 0% deviation for now
    
    // 2. Time Decay
    final diff = DateTime.now().millisecondsSinceEpoch - signal.timestamp;
    final seconds = (diff / 1000).clamp(0, 100).toDouble();
    
    // Score calculation
    // Base score 100
    // Subtract 1 point per second of age
    double score = 100.0 - seconds;
    
    // Subtract deviation penalty (huge)
    // If deviation > 0.2%, score drops to 0
    if (deviationPct > 0.20) {
        score = 0;
    }
    
    return score.clamp(0.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SniperState>(
      builder: (context, state, child) {
        final signal = state.activeSignal;
        
        // Empty State
        if (signal == null) {
            return Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    'WAITING FOR SIGNAL: ${state.selectedCoin}...',
                    style: GoogleFonts.orbitron(
                        color: Colors.grey[600],
                        fontSize: 16,
                        letterSpacing: 2,
                    ),
                  ),
                ),
            );
        }

        final isLong = signal.side == "LONG" || signal.side == "BUY";
        final color = isLong ? Colors.greenAccent : Colors.redAccent;
        final entryScore = _calculateEntryScore(signal);
        final isSafe = entryScore >= 80;
        final isRedZone = entryScore < 50;

        return Card(
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: color.withOpacity(0.6), width: 2),
          ),
          elevation: 10,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Header: Symbol + time ticker
                Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                       Text(
                          signal.symbol,
                          style: GoogleFonts.orbitron(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: _isExpired ? Colors.red.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: _isExpired ? Colors.red : Colors.blueAccent)
                            ),
                            child: Text(
                                _timeAgo,
                                style: GoogleFonts.orbitron(
                                    color: _isExpired ? Colors.red : Colors.blueAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold
                                ),
                            ),
                        )
                   ],
                ),
                
                // Side Badge
                Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4), // Reduced padding
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color)
                  ),
                  child: Text(
                    signal.side,
                    style: GoogleFonts.orbitron(
                        color: color,
                        fontSize: 24, // Slightly smaller
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                    ),
                  ),
                ),
                
                // Heatmap Gauge (Make flexible)
                Flexible(
                  flex: 2,
                  child: EntryGauge(score: entryScore),
                ),

                // Stats Grid
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _stat('ENTRY', '\$${signal.price.toStringAsFixed(2)}', Colors.white),
                        _stat('SCORE', _formatScore(signal.score), Colors.amber),
                      ],
                    ),
                    const SizedBox(height: 8), // Reduced
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _stat('TAKE PROFIT', '\$${signal.tp.toStringAsFixed(2)}', Colors.green),
                        _stat('STOP LOSS', '\$${signal.sl.toStringAsFixed(2)}', Colors.red),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 10), // Small spacer before button
                
                // EXECUTE BUTTON
                ScaleTransition(
                  scale: isSafe ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50, // Reduced height
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRedZone ? Colors.grey[800] : color,
                        foregroundColor: isRedZone ? Colors.grey : Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: isRedZone ? 0 : 10,
                        shadowColor: color.withOpacity(0.5),
                        padding: EdgeInsets.zero, // Remove internal padding
                      ),
                      onPressed: isRedZone ? null : widget.onExecute, // Disable if red zone
                      child: FittedBox( // Prevent text overflow
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  if (!isRedZone) const Icon(Icons.bolt, size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    isRedZone ? 'ENTRY OVEREXTENDED' : 'EXECUTE SNIPE',
                                    style: GoogleFonts.orbitron(
                                      fontSize: isRedZone ? 16 : 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                              ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatScore(double score) {
      if (score >= 1000000) {
          return '\$${(score / 1000000).toStringAsFixed(1)}M';
      }
      return '\$${(score / 1000).toStringAsFixed(0)}K';
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            label, 
            style: GoogleFonts.orbitron(
                color: Colors.grey, 
                fontSize: 12,
                fontWeight: FontWeight.w500
            )
        ),
        const SizedBox(height: 4),
        Text(
            value, 
            style: GoogleFonts.orbitron(
                color: color, 
                fontSize: 18, 
                fontWeight: FontWeight.bold
            )
        ),
      ],
    );
  }
}
