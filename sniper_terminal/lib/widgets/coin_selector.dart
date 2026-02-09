import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';

class CoinSelector extends StatelessWidget {
  const CoinSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final coins = Provider.of<SniperState>(context).availableCoins;
    
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: coins.length,
        itemBuilder: (context, index) {
          final coin = coins[index];
          return _buildCoinPill(context, coin);
        },
      ),
    );
  }

  Widget _buildCoinPill(BuildContext context, String coin) {
    return Consumer<SniperState>(
      builder: (context, state, child) {
        final isSelected = state.selectedCoin == coin;
        return GestureDetector(
          onTap: () => state.selectCoin(coin),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.greenAccent : Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? Colors.greenAccent : Colors.grey[800]!,
                width: 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: Center(
              child: Text(
                coin,
                style: GoogleFonts.orbitron(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
