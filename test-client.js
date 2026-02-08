// Simple WebSocket test client for Whale Radar
// Run with: node test-client.js

const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8080/ws');

let tradeCount = 0;
const exchangeStats = {};

ws.on('open', () => {
    console.log('🐋 Connected to Whale Radar Engine');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
});

ws.on('message', (data) => {
    const trade = JSON.parse(data);
    tradeCount++;
    
    // Track exchange stats
    if (!exchangeStats[trade.exchange]) {
        exchangeStats[trade.exchange] = { count: 0, totalVolume: 0 };
    }
    exchangeStats[trade.exchange].count++;
    exchangeStats[trade.exchange].totalVolume += trade.size;
    
    // Display trade
    const side = trade.side === 'buy' ? '🟢 BUY ' : '🔴 SELL';
    const timestamp = new Date(trade.timestamp).toLocaleTimeString();
    
    console.log(`[${timestamp}] ${trade.exchange.padEnd(12)} | ${side} | ${trade.size.toFixed(4)} BTC @ $${trade.price.toFixed(2)}`);
    
    // Show stats every 50 trades
    if (tradeCount % 50 === 0) {
        console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`📊 Stats after ${tradeCount} trades:`);
        Object.entries(exchangeStats)
            .sort((a, b) => b[1].count - a[1].count)
            .forEach(([exchange, stats]) => {
                console.log(`   ${exchange.padEnd(12)}: ${stats.count.toString().padStart(4)} trades | ${stats.totalVolume.toFixed(2)} BTC total`);
            });
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    }
});

ws.on('error', (error) => {
    console.error('❌ WebSocket error:', error.message);
});

ws.on('close', () => {
    console.log('\n🛑 Disconnected from Whale Radar Engine');
    console.log(`Total trades received: ${tradeCount}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n\n👋 Shutting down...');
    ws.close();
    process.exit(0);
});
