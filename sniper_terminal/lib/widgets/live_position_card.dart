import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/models/position.dart';

class LivePositionCard extends StatelessWidget {
  const LivePositionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SniperState>(
      builder: (context, state, child) {
        final position = state.activePosition;
        
        if (position == null) {
          return const SizedBox.shrink(); // Should be handled by parent, but safety net
        }

        final isProfit = position.unRealizedProfit >= 0;
        final pnlColor = isProfit ? Colors.greenAccent : Colors.redAccent;
        
        return Card(
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: pnlColor.withOpacity(0.6), width: 2),
          ),
          elevation: 10,
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // PREDATOR ADVICE BANNER
                _buildAdviceBanner(state, position, pnlColor),
                
                const SizedBox(height: 20),


                // Header: LIVE POSITION
                Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                       Row(
                           children: [
                               // SHIELD STATUS
                               AnimatedContainer(
                                   duration: const Duration(milliseconds: 500),
                                   padding: const EdgeInsets.all(4),
                                   decoration: BoxDecoration(
                                       shape: BoxShape.circle,
                                       boxShadow: state.isShieldSecured ? [
                                           BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 10, spreadRadius: 1)
                                       ] : [],
                                   ),
                                   child: Icon(
                                       state.isShieldSecured ? Icons.verified_user : Icons.security_outlined,
                                       color: state.isShieldSecured ? Colors.greenAccent : Colors.grey,
                                       size: 20,
                                   ),
                               ),
                               const SizedBox(width: 8),
                               Text(
                                  "LIVE POSITION",
                                  style: GoogleFonts.orbitron(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                           ],
                       ),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: pnlColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                                "${position.leverage.toStringAsFixed(0)}x ${position.marginType.toUpperCase()}",
                                style: GoogleFonts.orbitron(
                                    color: pnlColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold
                                ),
                            ),
                        )
                   ],
                ),
                
                const SizedBox(height: 20),
                
                // HUGE PNL DISPLAY
                Text(
                    "\$${position.unRealizedProfit.toStringAsFixed(2)}",
                    style: GoogleFonts.orbitron(
                        color: pnlColor,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                    ),
                ),
                Text(
                    "${position.roe.toStringAsFixed(2)}% ROE",
                    style: GoogleFonts.orbitron(
                        color: pnlColor.withOpacity(0.7),
                        fontSize: 18,
                        letterSpacing: 2,
                    ),
                ),
                
                const SizedBox(height: 30),

                // Stats Grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _stat(
                        'ENTRY (${position.side == "LONG" ? "BUY" : "SELL"})', 
                        '\$${_formatPrice(position.entryPrice)}',
                        labelColor: position.side == "LONG" ? Colors.greenAccent : Colors.redAccent
                    ),
                    _stat('MARK', '\$${_formatPrice(position.markPrice)}'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _stat('SIZE', '\$${(position.positionAmt.abs() * position.markPrice).toStringAsFixed(0)}'),
                    _stat('CURRENT', '\$${_formatPrice(position.markPrice)}', color: Colors.cyanAccent),
                    _stat('LIQ', '\$${_formatPrice(position.liquidationPrice)}', color: Colors.orange),
                  ],
                ),
                
                const SizedBox(height: 30),
                
                // PREDATOR WARNING
                if (state.whaleWarning)
                    Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(8)
                        ),
                        child: Row(
                            children: [
                                const Icon(Icons.warning, color: Colors.red),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(
                                        "WARNING: OPPOSING WHALE DETECTED - CONSIDER EXIT!",
                                        style: GoogleFonts.orbitron(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12
                                        ),
                                    ),
                                )
                            ],
                        ),
                    ),

                // EXIT BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red, // Panic Button Red
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 10,
                      shadowColor: Colors.red.withOpacity(0.5),
                    ),
                    onPressed: () async {
                        try {
                            await state.closeCurrentPosition();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('💥 Position CLOSED!')),
                            );
                        } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('❌ Close Failed: $e')),
                            );
                        }
                    },
                    child: Text(
                      'CLOSE POSITION',
                      style: GoogleFonts.orbitron(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
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

  Widget _buildAdviceBanner(SniperState state, Position position, Color pnlColor) {
      String message = "⏳ ANALYZING MARKET...";
      Color color = Colors.grey;
      IconData icon = Icons.hourglass_empty;

      // 0. PREDATOR ADVICE (Backend - Highest Priority)
      if (state.predatorAdvice != null) {
          message = "🧠 ${state.predatorAdvice}";
          color = Colors.purpleAccent; // Distinct color for backend insight
          icon = Icons.psychology;
          
          if (message.contains("EXIT")) {
              color = Colors.red;
              icon = Icons.warning_amber_rounded;
          } else if (message.contains("HOLD")) {
              color = Colors.blueAccent;
              icon = Icons.lock_clock;
          }
      }
      // 1. WHALE WARNING (Local Check)
      else if (state.whaleWarning) {
          message = "⚠️ OPPOSING WHALE: EXIT NOW!";
          color = Colors.red;
          icon = Icons.warning_amber_rounded;
      } 
      // 2. PROFIT TAKING
      else if (position.roe > 10.0) {
          message = "🚀 MOONING: TAKE PROFIT!";
          color = Colors.greenAccent;
          icon = Icons.rocket_launch;
      }
      else if (position.roe > 0.5) {
          message = "✅ IN PROFIT: SECURE GAINS?";
          color = Colors.green;
          icon = Icons.check_circle_outline;
      }
      // 3. HOLDING
      else if (position.roe > -5.0) {
          message = "💪 HOLD: TRENDING";
          color = Colors.amber;
          icon = Icons.trending_flat;
      }
      // 4. STOP LOSS
      else {
          message = "❌ STOP LOSS: CLOSE NOW";
          color = Colors.redAccent;
          icon = Icons.cancel_outlined;
      }

      return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.5))
          ),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 10),
                  Text(
                      message,
                      style: GoogleFonts.orbitron(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2
                      ),
                  ),
              ],
          ),
      );
  }

  Widget _stat(String label, String value, {Color color = Colors.white, Color labelColor = Colors.grey}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            label, 
            style: GoogleFonts.orbitron(
                color: labelColor, 
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

  String _formatPrice(double price) {
      if (price < 1.0) return price.toStringAsFixed(6);
      return price.round().toString(); // No decimals for values >= 1
  }
}
