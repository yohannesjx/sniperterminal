import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/sound_manager.dart';

class MuteButton extends ConsumerWidget {
  const MuteButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muteUntil = ref.watch(mutedProvider);
    final isMuted = muteUntil != null && DateTime.now().isBefore(muteUntil);

    return GestureDetector(
      onTap: () {
         if (isMuted) {
           // Unmute
           ref.read(mutedProvider.notifier).unmute();
         } else {
           // Smart Mute (Default 15m)
           ref.read(mutedProvider.notifier).muteFor(const Duration(minutes: 15));
           
           // Show snackbar
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: const Text('🔇 Muted for 15 minutes'),
               duration: const Duration(seconds: 2),
               backgroundColor: Colors.black87,
               behavior: SnackBarBehavior.floating,
             ),
           );
         }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMuted ? Colors.red.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: isMuted ? Colors.red : Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Icon(
          isMuted ? Icons.volume_off : Icons.volume_up,
          color: isMuted ? Colors.red : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
