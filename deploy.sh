#!/bin/bash

# Whale Radar - Quick Deploy Script
# Usage: ./deploy.sh [local|mvp|docker]

set -e

MODE=${1:-local}

echo "🐋 Whale Radar Deployment Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case $MODE in
  local)
    echo "📦 Mode: Local Development"
    echo "Installing dependencies..."
    go mod download
    echo "✅ Dependencies installed"
    echo ""
    echo "🚀 Starting engine..."
    go run main.go
    ;;
    
  mvp)
    echo "📦 Mode: MVP Deployment (Cross-Compile)"
    echo "Building for Linux AMD64..."
    GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o whale-radar-linux main.go
    echo "✅ Binary built: whale-radar-linux"
    echo ""
    echo "📊 Binary size:"
    ls -lh whale-radar-linux
    echo ""
    echo "📤 To deploy to your server, run:"
    echo "   scp whale-radar-linux user@your-server:/opt/whale-radar/"
    echo "   ssh user@your-server"
    echo "   cd /opt/whale-radar && chmod +x whale-radar-linux && ./whale-radar-linux"
    ;;
    
  docker)
    echo "📦 Mode: Production Docker"
    echo "Building Docker image..."
    docker build -t whale-radar:latest .
    echo "✅ Image built successfully"
    echo ""
    echo "🚀 Starting container..."
    docker run -d -p 8080:8080 --name whale-radar --restart unless-stopped whale-radar:latest
    echo "✅ Container started"
    echo ""
    echo "📊 Container status:"
    docker ps | grep whale-radar
    echo ""
    echo "📝 View logs with: docker logs -f whale-radar"
    echo "🛑 Stop with: docker stop whale-radar"
    ;;
    
  *)
    echo "❌ Invalid mode: $MODE"
    echo "Usage: ./deploy.sh [local|mvp|docker]"
    exit 1
    ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Deployment complete!"
