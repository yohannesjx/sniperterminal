import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../providers/alert_provider.dart';

class CoinSelector extends ConsumerWidget {
  const CoinSelector({super.key});

  final List<String> allCoins = const [
    'BTC', 'ETH', 'SOL', 'BNB', 'XRP', 
    'ADA', 'DOT', 'DOGE', 'PEPE', 'AVAX'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCoin = ref.watch(selectedCoinProvider);
    
    // Logic to determine visible coins
    // Always show top 4 + Selected + More
    List<String> displayCoins = ['BTC', 'ETH', 'SOL', 'BNB'];
    
    if (!displayCoins.contains(selectedCoin)) {
      displayCoins.add(selectedCoin);
    }
    
    displayCoins.add('+');

    return GlassmorphicContainer(
      width: double.infinity,
      height: 60,
      borderRadius: 30,
      blur: 20,
      alignment: Alignment.center,
      border: 2,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.1),
          Colors.white.withOpacity(0.05),
        ],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.5),
          Colors.white.withOpacity(0.2),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: displayCoins.map((coin) {
            final isSelected = selectedCoin == coin;
            final isMore = coin == '+';
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  if (isMore) {
                    _showCoinMenu(context, ref);
                  } else {
                    // Update selection
                    ref.read(selectedCoinProvider.notifier).state = coin;
                    
                    // CRITICAL: Reset price/symbol to prevent "stuck" UI
                    // CHECK CACHE FIRST: If we have a price, show it!
                    final cache = ref.read(priceCacheProvider);
                    if (cache.containsKey(coin)) {
                       ref.read(currentPriceProvider.notifier).state = cache[coin]!;
                    } else {
                       ref.read(currentPriceProvider.notifier).state = 0.0;
                    }
                    ref.read(latestSymbolProvider.notifier).state = coin;
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMore ? 16 : 20, 
                    vertical: 12
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25), // Pill shape
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              const Color(0xFF00FF41).withOpacity(0.3),
                              const Color(0xFF00FF41).withOpacity(0.1),
                            ],
                          )
                        : null,
                    border: isSelected
                        ? Border.all(
                            color: const Color(0xFF00FF41),
                            width: 2,
                          )
                        : Border.all(
                            color: Colors.transparent,
                            width: 2,
                          ),
                  ),
                  child: Text(
                    coin,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF00FF41)
                          : Colors.white.withOpacity(0.6),
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showCoinMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassmorphicContainer(
        width: double.infinity,
        height: 400,
        borderRadius: 30,
        blur: 20,
        alignment: Alignment.center,
        border: 2,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0a0e27).withOpacity(0.9),
            const Color(0xFF0a0e27).withOpacity(0.7),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.5),
            Colors.white.withOpacity(0.2),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              'Select Coin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.5,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: allCoins.length + 1, // +1 for ALL
                itemBuilder: (context, index) {
                  final coin = index == allCoins.length ? 'ALL' : allCoins[index];
                  final isSelected = ref.read(selectedCoinProvider) == coin;

                  return GestureDetector(
                    onTap: () {
                      ref.read(selectedCoinProvider.notifier).state = coin;
                      Navigator.pop(context);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? const Color(0xFF00FF41).withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected 
                              ? const Color(0xFF00FF41)
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Text(
                        coin,
                        style: TextStyle(
                          color: isSelected 
                              ? const Color(0xFF00FF41)
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
