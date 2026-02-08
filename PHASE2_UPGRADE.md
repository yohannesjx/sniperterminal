# Phase 2 Upgrade: Quick Reference Guide

## What Changed

### 1. Alert System
Replaced raw `Trade` objects with intelligent `Alert` objects:

```go
type Alert struct {
    Type      string  // "TRADE", "WHALE", "LIQUIDATION", "ICEBERG"
    Level     int     // 1-5 priority
    Message   string  // Human-readable description
    Data      Trade   // Original trade data
}
```

### 2. Binance Liquidation Stream
Added second WebSocket connection:
- URL: `wss://fstream.binance.com/ws/!forceOrder@arr`
- Monitors force liquidations in real-time
- Creates Level 4 alerts with 💀 emoji

### 3. Analyzer Logic

**Whale Detection:**
- 5+ BTC = Level 3 Whale Alert 🐋
- 20+ BTC = Level 5 Mega Whale Alert 🐋

**Iceberg Detection:**
- Tracks volume at each price level
- 50+ BTC at same price within 60s = Level 4 Iceberg Alert 🧊

### 4. WebSocket API Update

**Before (Phase 1):**
```json
{
  "price": 76334.40,
  "size": 6.9290,
  "side": "buy",
  "exchange": "Binance",
  "timestamp": 1706832000000
}
```

**After (Phase 2):**
```json
{
  "type": "WHALE",
  "level": 3,
  "message": "🐋 Whale Alert: 6.9290 BTC buy on Binance @ $76334.40",
  "data": {
    "price": 76334.40,
    "size": 6.9290,
    "side": "buy",
    "exchange": "Binance",
    "timestamp": 1706832000000
  }
}
```

## Alert Types & Levels

| Type | Level | Trigger | Color |
|------|-------|---------|-------|
| TRADE | 1 | 0.1+ BTC | Green/Red |
| WHALE | 3 | 5+ BTC | Cyan |
| WHALE | 5 | 20+ BTC | Yellow |
| LIQUIDATION | 4 | Binance force order | Magenta |
| ICEBERG | 4 | 50+ BTC at price | Blue |

## Running the Upgraded Engine

```bash
# Same as before
go run main.go

# Or use deployment script
./deploy.sh local
```

## Testing Alert Types

### To See Whale Alerts
Wait for large trades (5+ BTC) - they appear frequently on Binance during volatile periods.

### To See Liquidation Alerts
Already streaming! Check console logs for `[ALERT L4] 💀 LIQUIDATION`

### To See Iceberg Alerts
Requires 50+ BTC accumulated at same price within 60 seconds - rare but detectable during major support/resistance levels.

## Flutter Integration Changes

Update your WebSocket message handler to parse `Alert` instead of `Trade`:

```dart
// Before
final trade = Trade.fromJson(jsonDecode(message));

// After
final alert = Alert.fromJson(jsonDecode(message));
final trade = alert.data;  // Original trade data still available
```

## Key Files Modified

- `main.go` - Added Alert system, Analyzer, and liquidation stream
- Dashboard UI - Color-coded alert display

## Performance

- **Latency**: Sub-millisecond analysis
- **Memory**: Auto-cleanup every 10 seconds
- **Concurrency**: Thread-safe with RWMutex
- **Reliability**: Same auto-reconnect as Phase 1
