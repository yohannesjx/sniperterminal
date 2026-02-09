import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sniper_terminal/providers/sniper_state.dart';
import 'package:sniper_terminal/services/websocket_service.dart';
import 'package:sniper_terminal/services/api_service.dart'; // NEW
import 'package:sniper_terminal/models/position.dart';
import 'package:vibration/vibration.dart';

class LiveSniperHUD extends StatefulWidget {
  const LiveSniperHUD({super.key});

  @override
  State<LiveSniperHUD> createState() => _LiveSniperHUDState();
}

class _LiveSniperHUDState extends State<LiveSniperHUD> with SingleTickerProviderStateMixin {

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  double _currentPressure = 0.0; // 0.0 to 1.0 (or higher)
  String _lastLiquidation = "SCANNING FOR REKT TRADERS...";
  StreamSubscription? _alertSub;

  // Slider State
  double _sliderValue = 0.0;
  double _targetPrice = 0.0;
  bool _isTargetConfirmed = false;
  bool _sliderInitialized = false;

  @override
  void initState() {
    super.initState();
    // Pulsing Animation for ROI
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to Alert Stream
    _alertSub = WebSocketService().alertStream.listen((data) {
        if (!mounted) return;
        
        final type = data['type'];
        final symbol = data['symbol'];
        final state = Provider.of<SniperState>(context, listen: false);
        final activeSymbol = state.activePosition?.symbol ?? "";

        // 1. WHALE PRESSURE (Current Symbol Only)
        if (type == 'WHALE' && symbol == activeSymbol) {
             double ratio = double.tryParse(data['ratio'].toString()) ?? 0.0;
             // Normalize: Ratio 10 = Full Bar. 
             double pressure = ratio / 10.0; 
             if (pressure > 1.0) pressure = 1.0;
             
             setState(() {
                 _currentPressure = pressure;
             });
             
             // Decay pressure after 5 seconds
             Future.delayed(const Duration(seconds: 10), () {
                 if (mounted) setState(() => _currentPressure = 0.0);
             });
        }

        // 2. LIQUIDATOR TICKER (All Liquidations)
        if (type == 'LIQUIDATION') {
            setState(() {
                _lastLiquidation = data['message'].replaceAll("💀 LIQUIDATION:", "").trim();
            });
        }

        // 3. TARGET CONFIRMED (Green Thumb)
        if (type == 'TARGET_CONFIRMED' && symbol == activeSymbol) {
             setState(() {
                 _isTargetConfirmed = true;
                 if (state.whaleWarning) {
                   try { Vibration.vibrate(pattern: [50, 100, 50, 100]); } catch (_) {} // Double Pulse
                 }
             });
        }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sliderInitialized) {
        final state = Provider.of<SniperState>(context, listen: false);
        if (state.activePosition != null) {
            _initSlider(state.activePosition!);
        }
    }
  }

  void _initSlider(Position pos) {
      if (_sliderInitialized) return;

      // If target is already set, reverse calc profit to set slider
      if (_targetPrice > 0) {
          double diff = _targetPrice - pos.entryPrice;
          if (pos.positionAmt < 0) diff = pos.entryPrice - _targetPrice;
          
          double profit = diff * pos.positionAmt.abs();
          _sliderValue = profit.clamp(0.0, 100.0);
      } else {
          // Default to 10 USDT Target
          _sliderValue = 10.0;
          _targetPrice = _calcPriceFromProfit(pos, 10.0);
      }
      
      _sliderInitialized = true;
  }

  double _calcPriceFromProfit(Position pos, double profitUsdt) {
      if (pos.positionAmt == 0) return pos.markPrice;
      
      double priceDist = profitUsdt / pos.positionAmt.abs();
      
      if (pos.positionAmt > 0) { // LONG
           return pos.entryPrice + priceDist;
      } else { // SHORT
           return pos.entryPrice - priceDist;
      }
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            label, 
            style: GoogleFonts.robotoMono(
                color: Colors.grey, 
                fontSize: 10,
                fontWeight: FontWeight.bold
            )
        ),
        const SizedBox(height: 2),
        Text(
            value, 
            style: GoogleFonts.robotoMono(
                color: color, 
                fontSize: 14, 
                fontWeight: FontWeight.bold
            )
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SniperState>(
      builder: (context, state, child) {
        final position = state.activePosition;
        if (position == null) return const SizedBox.shrink();

        final pnl = position.unRealizedProfit;
        final isProfit = pnl >= 0;
        final pnlColor = isProfit ? const Color(0xFF00FF00) : const Color(0xFFFF0000); 

        // CALCULATED METRICS
        double sizeUsdt = position.notional;
        if (sizeUsdt == 0) sizeUsdt = position.absAmt * position.markPrice;

        double marginUsdt = position.isolatedMargin;
        if (marginUsdt == 0) marginUsdt = sizeUsdt / position.leverage;

        // Risk / Safety Ratio (Distance to Liquidation)
        // If Liq is 0, risk is 0.
        double riskRatio = 0.0;
        if (position.liquidationPrice > 0) {
             double dist = (position.markPrice - position.liquidationPrice).abs();
             double totalDist = position.markPrice; 
             riskRatio = (1.0 - (dist / totalDist)) * 100; // Rough proximity
             // Better: Risk = (Maint Margin / Margin Balance) proxy?
             // Let's use Liq Distance %. The closer to Liq, the higher the risk.
             // Actually, usually traders want "Margin Ratio" = Maint / Balance.
             // Let's call it "Safety" instead? User asked for "Margin Ratio".
             // Let's show "Risk Lvl" based on Liq Proximity.
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), 
          decoration: BoxDecoration(
            color: Colors.black, 
            border: Border.all(color: pnlColor, width: 2),
            borderRadius: BorderRadius.circular(8), // Less sharp
            boxShadow: [
              BoxShadow(
                color: pnlColor.withOpacity(0.2),
                blurRadius: 15,
                spreadRadius: 2,
              )
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
                // TOP ROW: SYMBOL | LEVERAGE | STATUS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                      Row(
                          children: [
                              Text(
                                  position.symbol,
                                  style: GoogleFonts.orbitron(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1
                                  )
                              ),
                              const SizedBox(width: 8),
                              const SizedBox(width: 8),
                              
                              // SIDE PILL (S/B)
                              Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: position.positionAmt > 0 ? Colors.green : Colors.red,
                                      borderRadius: BorderRadius.circular(4)
                                  ),
                                  child: Text(
                                      position.positionAmt > 0 ? "B" : "S",
                                      style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                                  ),
                              ),
                              const SizedBox(width: 4),

                              Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      border: Border.all(color: Colors.grey[700]!),
                                      borderRadius: BorderRadius.circular(4)
                                  ),
                                  child: Text(
                                      "${position.marginType.toLowerCase().contains("iso") ? "ISO" : "CROS"} ${position.leverage.toStringAsFixed(0)}X",
                                      style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                                  ),
                              ),
                          ],
                      ),
                      
                      // ROE BADGE
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: pnlColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: pnlColor.withOpacity(0.5))
                          ),
                          child: Text(
                              "${position.roe >= 0 ? "+" : ""}${position.roe.toStringAsFixed(2)}%",
                              style: GoogleFonts.robotoMono(
                                  color: pnlColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold
                              )
                          ),
                      )
                  ],
                ),
                
                const SizedBox(height: 20), // Loosened spacing

                // MAIN PNL DISPLAY
                Column(
                    children: [
                        Text(
                            "UNREALIZED PNL",
                            style: GoogleFonts.orbitron(color: Colors.grey[600], fontSize: 10, letterSpacing: 2)
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          child: Text(
                              "\$${pnl.toStringAsFixed(2)}",
                              style: GoogleFonts.orbitron(
                                  color: pnlColor,
                                  fontSize: 42, 
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                      Shadow(color: pnlColor.withOpacity(0.5), blurRadius: 20)
                                  ]
                              )
                          ),
                        ),
                    ],
                ),

                const SizedBox(height: 25), // Loosened spacing

                // DATA GRID (2 Rows x 3 Cols)
                Table(
                    children: [
                        TableRow(
                            children: [
                                _statCell("ENTRY", "\$${position.entryPrice.toStringAsFixed(0)}", Colors.white),
                                _statCell("MARK", "\$${position.markPrice.toStringAsFixed(0)}", Colors.cyanAccent),
                                _statCell("LIQ PRICE", "\$${position.liquidationPrice.toStringAsFixed(0)}", Colors.orange),
                            ]
                        ),
                        // SPACING ROW
                        const TableRow(children: [SizedBox(height: 16), SizedBox(height: 16), SizedBox(height: 16)]),
                        
                        TableRow(
                            children: [
                                _statCell("SIZE (USDT)", "\$${sizeUsdt.toStringAsFixed(0)}", Colors.white),
                                _statCell("MARGIN", "\$${marginUsdt.toStringAsFixed(0)}", Colors.white),
                                
                                // STOP LOSS DISPLAY
                                Builder(
                                  builder: (context) {
                                    // Try to get SL from Active Signal
                                    double stopLoss = 0.0;
                                    if (state.activeSignal != null && state.activeSignal!.symbol == position.symbol) {
                                        stopLoss = state.activeSignal!.sl;
                                    }
                                    
                                    // Fallback: 1% from Entry
                                    if (stopLoss == 0) {
                                        if (position.positionAmt > 0) {
                                            stopLoss = position.entryPrice * 0.99;
                                        } else {
                                            stopLoss = position.entryPrice * 1.01;
                                        }
                                    }
                                    
                                    return _statCell("STOP LOSS", "\$${stopLoss.toStringAsFixed(2)}", Colors.orange);
                                  }
                                ),
                            ]
                        ),
                    ],
                ),
  
                const SizedBox(height: 25), // Loosened spacing
  
                // SLIDER & EXIT
                Column(
                   crossAxisAlignment: CrossAxisAlignment.stretch,
                   children: [
                      Row( // Slider Labels
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                               Text("AUTO-TP", style: GoogleFonts.orbitron(color: Colors.grey, fontSize: 10)),
                               Text(
                                   _sliderValue == 0 ? "OFF" : "+\$${_sliderValue.toStringAsFixed(0)}",
                                   style: GoogleFonts.orbitron(color: _isTargetConfirmed ? Colors.greenAccent : Colors.white, fontSize: 12)
                               )
                          ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderThemeData(
                            activeTrackColor: Colors.greenAccent,
                            inactiveTrackColor: Colors.grey[900],
                            thumbColor: Colors.white,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        ),
                        child: Slider(
                            value: _sliderValue,
                            min: 0,
                            max: 100, 
                            divisions: 100,
                            onChanged: (val) {
                                setState(() {
                                    _sliderValue = val;
                                    _targetPrice = _calcPriceFromProfit(position, val);
                                    _isTargetConfirmed = false;
                                });
                            },
                            onChangeEnd: (val) {
                                try { Vibration.vibrate(duration: 50); } catch (_) {}
                                if (val > 0) {
                                     // ApiService().setExitTarget(...) -> OLD
                                     // SniperState.setProfitTarget(...) -> NEW
                                     Provider.of<SniperState>(context, listen: false)
                                         .setProfitTarget(_targetPrice)
                                         .then((_) => ScaffoldMessenger.of(context).showSnackBar(
                                             const SnackBar(content: Text("✅ Target Set (Limit Order)"))
                                         ))
                                         .catchError((e) => ScaffoldMessenger.of(context).showSnackBar(
                                             SnackBar(content: Text("❌ Failed: $e"))
                                         ));
                                }
                            },
                        ),
                      ),
                   ],
                ),
                
                const SizedBox(height: 16),

                // BIG EXIT BUTTON
                SizedBox(
                    width: double.infinity, 
                    height: 50, 
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.9),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), 
                            elevation: 5,
                            shadowColor: Colors.redAccent.withOpacity(0.5),
                        ),
                        onPressed: () async {
                            try { Vibration.vibrate(duration: 200); } catch (_) {}
                            try {
                                  await state.closeCurrentPosition();
                            } catch (e) {
                                  // Error
                            }
                        },
                        child: Text(
                            "MARKET EXIT",
                            style: GoogleFonts.orbitron(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3
                            )
                        ),
                    ),
                )
            ],
          ),
        );
      },
    );
  }

  Widget _statCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
            label, 
            style: GoogleFonts.robotoMono(
                color: Colors.grey[600], 
                fontSize: 9, 
                fontWeight: FontWeight.bold
            )
        ),
        const SizedBox(height: 4),
        Text(
            value, 
            style: GoogleFonts.orbitron(
                color: color, 
                fontSize: 14, 
                fontWeight: FontWeight.bold
            )
        ),
      ],
    );
  }

  Color _getAdviceColor(double roe) {
      if (roe >= 10.0) return Colors.greenAccent;
      if (roe >= 0.5) return Colors.green;
      if (roe >= -5.0) return Colors.amber;
      return Colors.red;
  }

  IconData _getAdviceIcon(double roe) {
      if (roe >= 10.0) return Icons.rocket_launch;
      if (roe >= 0.5) return Icons.check_circle;
      if (roe >= -5.0) return Icons.update; // Hold/Wait
      return Icons.warning_amber_rounded;
  }

  String _getAdviceText(double roe) {
      if (roe >= 10.0) return "TAKE\nPROFIT"; 
      if (roe >= 0.5) return "SECURE\nNOW";
      if (roe >= -5.0) return "HOLD\nON";
      return "STOP\nLOSS";
  }

}
