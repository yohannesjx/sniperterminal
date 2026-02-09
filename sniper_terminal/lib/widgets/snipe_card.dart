import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sniper_terminal/models/signal.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';

class SnipeCard extends StatelessWidget {
  final Signal signal;

  const SnipeCard({super.key, required this.signal});

  @override
  Widget build(BuildContext context) {
    bool isLong = signal.side == "LONG";
    Color accentColor = isLong ? Colors.greenAccent : Colors.redAccent;

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        side: BorderSide(color: accentColor, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isLong ? Icons.trending_up : Icons.trending_down,
                      color: accentColor,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      signal.symbol,
                      style: GoogleFonts.orbitron(
                          fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isLong ? "BUY/LONG" : "SELL/SHORT",
                    style: GoogleFonts.orbitron(
                        color: accentColor, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),

            // WHALE METRICS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric("Whale Volume", "\$${(signal.score / 1000).toStringAsFixed(0)}K"),
                _buildMetric("Ratio", signal.tier.contains("Tier") ? "2.5x" : "1.2x"), // Placeholder until Ratio is in Signal model explicitly
                _buildMetric("Entry", signal.price.toStringAsFixed(4)),
              ],
            ),
            const SizedBox(height: 20),

            // WHALE WALL VISUALIZATION (Abstract)
            Container(
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [accentColor.withValues(alpha: 0.1), accentColor],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Center(
                child: Text(
                  "WHALE WALL DETECTED",
                  style: GoogleFonts.orbitron(
                      color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // SNIPE BUTTON
            SizedBox(
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 10,
                  shadowColor: accentColor.withValues(alpha: 0.5),
                ),
                onPressed: () {
                   Provider.of<SniperState>(context, listen: false).executeSnipe(signal);
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🚀 SNIPING ${signal.symbol}!')));
                },
                child: Text(
                  "SNIPE NOW (10x)",
                  style: GoogleFonts.orbitron(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.roboto(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
