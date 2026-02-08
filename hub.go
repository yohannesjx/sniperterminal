package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Hub maintains the set of active clients and broadcasts messages
type Hub struct {
	clients   map[*websocket.Conn]bool
	clientsMu sync.Mutex
	upgrader  websocket.Upgrader
}

func NewHub() *Hub {
	return &Hub{
		clients: make(map[*websocket.Conn]bool),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for V1 (Development/Mobile)
			},
		},
	}
}

// HandleWebSocket manages the websocket connection lifecycle
func (h *Hub) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	log.Printf("Headers: %v", r.Header)
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Upgrade error: %v", err)
		return
	}

	h.register(conn)

	// Send Initial Connection Status
	initMsg := map[string]interface{}{
		"type":        "connection_init",
		"status":      "connected",
		"binance_api": BinanceStatus,
		"exchange":    ExchangeMode,
		"timestamp":   time.Now().UnixMilli(),
	}
	conn.WriteJSON(initMsg)

	// Keep connection alive (Read Loop)
	// We don't process incoming messages in V1, but the loop is required to detect disconnects
	defer func() {
		h.unregister(conn)
		conn.Close()
	}()

	// WebSocket Heartbeat Config
	const (
		writeWait      = 10 * time.Second
		pongWait       = 60 * time.Second
		pingPeriod     = (pongWait * 9) / 10
		maxMessageSize = 512
	)

	conn.SetReadLimit(maxMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error { conn.SetReadDeadline(time.Now().Add(pongWait)); return nil })

	// Start Pinger
	go func() {
		ticker := time.NewTicker(pingPeriod)
		defer ticker.Stop()
		for range ticker.C {
			if err := conn.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(writeWait)); err != nil {
				return // Stop Pinger if write fails
			}
		}
	}()

	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			break
		}
	}
}

func (h *Hub) register(conn *websocket.Conn) {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()
	h.clients[conn] = true
	log.Printf("Client connected. Total clients: %d", len(h.clients))
}

func (h *Hub) unregister(conn *websocket.Conn) {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()
	if _, ok := h.clients[conn]; ok {
		delete(h.clients, conn)
		log.Printf("Client disconnected. Total clients: %d", len(h.clients))
	}
}

// Broadcast sends a message to all connected clients
func (h *Hub) Broadcast(msg interface{}) {
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Broadcast marshal error: %v", err)
		return
	}

	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	for client := range h.clients {
		if err := client.WriteMessage(websocket.TextMessage, data); err != nil {
			log.Printf("Write error: %v", err)
			client.Close()
			delete(h.clients, client)
		}
	}
}

// ============================================================================
// PRICE THROTTLER (Live Ticker)
// ============================================================================

type TickerMessage struct {
	Type   string  `json:"type"` // "ticker"
	Symbol string  `json:"symbol"`
	Price  float64 `json:"price"`
}

type PriceThrottler struct {
	hub        *Hub
	lastPrices map[string]float64
	mu         sync.RWMutex
}

func NewPriceThrottler(hub *Hub) *PriceThrottler {
	return &PriceThrottler{
		hub:        hub,
		lastPrices: make(map[string]float64),
	}
}

func (pt *PriceThrottler) UpdatePrice(symbol string, price float64) {
	pt.mu.Lock()
	pt.lastPrices[symbol] = price
	pt.mu.Unlock()
}

func (pt *PriceThrottler) Start() {
	ticker := time.NewTicker(200 * time.Millisecond) // 5x per second
	defer ticker.Stop()

	for range ticker.C {
		pt.mu.RLock()
		// Copy map to minimize lock time
		snapshot := make(map[string]float64)
		for k, v := range pt.lastPrices {
			snapshot[k] = v
		}
		pt.mu.RUnlock()

		if len(snapshot) == 0 {
			continue
		}

		// Broadcast updates for each symbol
		for symbol, price := range snapshot {
			msg := TickerMessage{
				Type:   "ticker",
				Symbol: symbol,
				Price:  price,
			}
			pt.hub.Broadcast(msg)
		}
	}
}
