import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';

class FleetControlBar extends StatelessWidget {
  const FleetControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SniperState>(
      builder: (context, state, child) {
        double totalPnL = state.cumulativeProfit;
        Color pnlColor = totalPnL >= 0 ? Colors.greenAccent : Colors.redAccent;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            border: Border(top: BorderSide(color: Colors.grey[800]!, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // PnL Display
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("FLEET PnL",
                      style: GoogleFonts.roboto(color: Colors.grey, fontSize: 12)),
                  Text(
                    "\$${totalPnL.toStringAsFixed(2)}",
                    style: GoogleFonts.orbitron(
                        color: pnlColor, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              
              // Close All Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent, // Keep green as it's for profit taking
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: totalPnL > 1.0 
                    ? () {
                        state.closeAllInProfit();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('💰 SECURING FLEET PROFITS!')));
                      }
                    : null, // Disable if no profit
                icon: const Icon(Icons.check_circle, color: Colors.black),
                label: Text(
                  "CLOSE PROFIT",
                  style: GoogleFonts.orbitron(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
