import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sniper_terminal/services/system_health_service.dart';

class SystemHealthBar extends StatefulWidget {
  final SystemHealthStatus status;
  final VoidCallback onTap;
  
  const SystemHealthBar({
    super.key,
    required this.status,
    required this.onTap,
  });

  @override
  State<SystemHealthBar> createState() => _SystemHealthBarState();
}

class _SystemHealthBarState extends State<SystemHealthBar> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isHealthy = widget.status.isAllHealthy;
    final barColor = isHealthy ? Colors.greenAccent : Colors.redAccent;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          bottom: BorderSide(color: barColor, width: 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed Bar
          InkWell(
            onTap: _toggleExpanded,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Status Icon
                  Icon(
                    isHealthy ? Icons.check_circle : Icons.error,
                    color: barColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  
                  // Status Text
                  Expanded(
                    child: Text(
                      isHealthy ? 'ALL SYSTEMS OPERATIONAL' : 'SYSTEM OFFLINE',
                      style: GoogleFonts.orbitron(
                        color: barColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  
                  // Quick Indicators
                  _buildQuickIndicator(
                    Icons.hub,
                    widget.status.scannerHubConnected,
                    '${widget.status.backendLatencyMs}ms',
                  ),
                  const SizedBox(width: 8),
                  _buildQuickIndicator(
                    Icons.flash_on,
                    widget.status.exchangeApiHealthy,
                    '${widget.status.exchangeLatencyMs}ms',
                  ),
                  const SizedBox(width: 8),
                  _buildQuickIndicator(
                    Icons.verified_user,
                    widget.status.authStateValid,
                    null,
                  ),
                  const SizedBox(width: 8),
                  _buildQuickIndicator(
                    Icons.access_time,
                    widget.status.timeSyncHealthy,
                    null,
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Expand Icon
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded Details
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    'Scanner Hub',
                    Icons.hub,
                    widget.status.scannerHubConnected,
                    'Backend WebSocket',
                    '${widget.status.backendLatencyMs}ms',
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    'Exchange API',
                    Icons.flash_on,
                    widget.status.exchangeApiHealthy,
                    'Binance Futures',
                    '${widget.status.exchangeLatencyMs}ms',
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    'Auth State',
                    Icons.verified_user,
                    widget.status.authStateValid,
                    'API Keys Valid',
                    null,
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    'Time Sync',
                    Icons.access_time,
                    widget.status.timeSyncHealthy,
                    'Device Clock',
                    null,
                  ),
                  const SizedBox(height: 12),
                  // Last Check Time
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Last Successful Check: ${widget.status.lastCheckTime.toString().split('.')[0]}',
                      style: GoogleFonts.robotoMono(color: Colors.grey[500], fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickIndicator(IconData icon, bool isHealthy, String? metric) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isHealthy ? Colors.greenAccent.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHealthy ? Colors.greenAccent : Colors.redAccent,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isHealthy ? Colors.greenAccent : Colors.redAccent,
            size: 14,
          ),
          if (metric != null) ...[
            const SizedBox(width: 4),
            Text(
              metric,
              style: GoogleFonts.robotoMono(
                color: isHealthy ? Colors.greenAccent : Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String title,
    IconData icon,
    bool isHealthy,
    String description,
    String? metric,
  ) {
    final color = isHealthy ? Colors.greenAccent : Colors.redAccent;
    
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                description,
                style: GoogleFonts.roboto(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (metric != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 1),
            ),
            child: Text(
              metric,
              style: GoogleFonts.robotoMono(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (metric == null)
          Icon(
            isHealthy ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 20,
          ),
      ],
    );
  }
}
