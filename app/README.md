# Whale Radar Flutter App

A real-time cryptocurrency whale tracking radar with stunning visualizations.

## Features

- 🎯 Real-time WebSocket connection to whale tracking backend
- 🌊 Animated radar visualization with rotating scanner
- 🐋 Asset-based blips (whale.png, iceberg.png) with pulse animations
- 💎 Glassmorphic UI with coin selector (BTC, ETH, SOL, ALL)
- 📊 Live price display and ticker tape
- 🎨 Neon green/purple/cyan color scheme

## Setup

1. **Install dependencies:**
   ```bash
   cd app
   flutter pub get
   ```

2. **Generate JSON serialization code:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Add PNG assets:**
   Place the following files in `app/assets/`:
   - `whale.png` - Neon purple whale icon
   - `iceberg.png` - Neon blue iceberg icon
   - `live_feed.png` - Live feed status badge
   - `radar_grid.png` - Green radar grid background

4. **Run the app:**
   ```bash
   flutter run
   ```

## Architecture

- **State Management:** Riverpod
- **WebSocket:** web_socket_channel
- **UI:** Custom painters, glassmorphism, animations

## File Structure

```
app/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   └── alert.dart
│   ├── providers/
│   │   └── alert_provider.dart
│   ├── screens/
│   │   └── main_screen.dart
│   └── widgets/
│       ├── coin_selector.dart
│       └── radar_view.dart
├── assets/
│   ├── whale.png
│   ├── iceberg.png
│   ├── live_feed.png
│   └── radar_grid.png
└── pubspec.yaml
```

## Configuration

Update WebSocket URL in `lib/providers/alert_provider.dart`:
```dart
final webSocketUrlProvider = Provider<String>((ref) {
  return 'ws://localhost:8080/ws'; // Change to your backend URL
});
```

## Alert Types

- **WHALE** (Level 3): Purple whale icon
- **MEGA_WHALE** (Level 5): Pink whale icon (1.5x scale)
- **ICEBERG** (Level 4): Cyan iceberg icon

## Coin Filtering

Tap coin selector pills to filter alerts:
- **BTC**: Show only Bitcoin alerts
- **ETH**: Show only Ethereum alerts
- **SOL**: Show only Solana alerts
- **ALL**: Show all coins
