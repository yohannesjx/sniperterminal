# 🐋 Whale Radar - High-Frequency Crypto Scanner

A production-grade, high-performance cryptocurrency futures scanner that aggregates real-time trade data from 7 major exchanges.

## 🎯 Features

- **7 Major Exchanges**: Binance, Bybit, OKX, Kraken, Coinbase, Crypto.com, KuCoin
- **Real-time WebSocket Feeds**: Sub-millisecond latency
- **Automatic Reconnection**: Resilient to network failures
- **Trade Normalization**: All sizes converted to BTC
- **Trash Filter**: Automatically filters trades < 0.1 BTC
- **WebSocket Broadcasting**: Live feed on port 8080
- **Built-in Web UI**: Monitor trades in your browser

## 🚀 Quick Start

### Local Development

```bash
# Install dependencies
go mod download

# Run the engine
go run main.go
```

Open your browser to `http://localhost:8080` to see the live feed.

### MVP Deployment (Cross-Compile + SCP)

```bash
# Build for Linux (most VPS)
GOOS=linux GOARCH=amd64 go build -o whale-radar-linux main.go

# Upload to server
scp whale-radar-linux user@your-server:/opt/whale-radar/

# SSH and run
ssh user@your-server
cd /opt/whale-radar
chmod +x whale-radar-linux
./whale-radar-linux
```

### Production Deployment (Docker)

```bash
# Build Docker image
docker build -t whale-radar:latest .

# Run container
docker run -d -p 8080:8080 --name whale-radar whale-radar:latest

# View logs
docker logs -f whale-radar
```

## 📊 Exchange Details

| Exchange | Market Type | Symbol | Notes |
|----------|-------------|--------|-------|
| Binance | Futures | BTCUSDT | Perpetual futures |
| Bybit | Linear Futures | BTCUSDT | V5 API |
| OKX | Swap | BTC-USDT-SWAP | Size in $100 contracts |
| Kraken | Futures | PI_XBTUSD | Perpetual inverse |
| Coinbase | Spot | BTC-USD | Advanced Trade API |
| Crypto.com | Derivatives | BTC_USD_PERP | Perpetual |
| KuCoin | Futures | XBTUSDTM | Requires token handshake |

## 🔧 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Exchange Interface                    │
│                  Start(out chan<- Trade)                 │
└─────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   ┌────▼────┐         ┌────▼────┐        ┌────▼────┐
   │ Binance │         │  Bybit  │        │   OKX   │
   └────┬────┘         └────┬────┘        └────┬────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                    ┌───────▼────────┐
                    │  Unified Chan  │
                    │  (1000 buffer) │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  Trash Filter  │
                    │   (< 0.1 BTC)  │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │   Broadcast    │
                    │  WebSocket     │
                    │   :8080/ws     │
                    └────────────────┘
```

## 📡 WebSocket API

Connect to `ws://localhost:8080/ws` to receive real-time trades.

### Trade Format

```json
{
  "price": 45123.50,
  "size": 1.2345,
  "side": "buy",
  "exchange": "Binance",
  "timestamp": 1706832000000
}
```

## 🛠️ Build Commands Reference

```bash
# Local run
go run main.go

# Build for current platform
go build -o whale-radar main.go

# Cross-compile for Linux
GOOS=linux GOARCH=amd64 go build -o whale-radar-linux main.go

# Cross-compile for macOS (ARM)
GOOS=darwin GOARCH=arm64 go build -o whale-radar-mac main.go

# Cross-compile for Windows
GOOS=windows GOARCH=amd64 go build -o whale-radar.exe main.go

# Build with optimizations (smaller binary)
go build -ldflags="-s -w" -o whale-radar main.go
```

## 🐳 Docker Commands

```bash
# Build image
docker build -t whale-radar:latest .

# Run detached
docker run -d -p 8080:8080 --name whale-radar whale-radar:latest

# View logs
docker logs -f whale-radar

# Stop and remove
docker stop whale-radar && docker rm whale-radar

# Restart
docker restart whale-radar
```

## 📝 Notes

- **OKX Size Conversion**: OKX reports size in $100 contracts. The engine converts this to BTC: `(contracts * 100) / price`
- **KuCoin Handshake**: KuCoin requires an HTTP POST to get a WebSocket token before connecting
- **Reconnection Logic**: All exchanges have automatic reconnection with exponential backoff
- **Trash Filter**: Trades below 0.1 BTC are automatically discarded to reduce noise

## 🎨 Next Steps (Flutter Frontend)

The WebSocket endpoint is ready at `ws://localhost:8080/ws`. Connect your Flutter app to visualize the "Command Center" HUD.

## 📄 License

MIT
