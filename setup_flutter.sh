#!/bin/bash

# Whale Radar Flutter App Setup Script

echo "🐋 Whale Radar Flutter App Setup"
echo "=================================="
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first."
    echo "Visit: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter found: $(flutter --version | head -n 1)"
echo ""

# Navigate to app directory
cd "$(dirname "$0")/app" || exit

# Install dependencies
echo "📦 Installing dependencies..."
flutter pub get

# Generate JSON serialization code
echo "🔧 Generating JSON serialization code..."
flutter pub run build_runner build --delete-conflicting-outputs

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Add PNG assets to app/assets/:"
echo "   - whale.png (Neon purple whale icon)"
echo "   - iceberg.png (Neon blue iceberg icon)"
echo "   - live_feed.png (Live feed status badge)"
echo "   - radar_grid.png (Green radar grid background)"
echo ""
echo "2. Make sure the Go backend is running:"
echo "   cd .. && go run main.go"
echo ""
echo "3. Run the Flutter app:"
echo "   cd app && flutter run"
echo ""
echo "🚀 Ready to track whales!"
