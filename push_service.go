package main

import (
	"context"
	"fmt"
	"log"
	"os"

	firebase "firebase.google.com/go"
	"firebase.google.com/go/messaging"
	"google.golang.org/api/option"
)

type PushService struct {
	client *messaging.Client
	app    *firebase.App
}

// 1. Define Message Structure
type PushMessage struct {
	Topic string
	Title string
	Body  string
	Data  map[string]string
}

// 2. Create Global Buffered Channel
var pushQueue = make(chan PushMessage, 500)

func NewPushService() *PushService {
	// 1. Check for credentials file
	credFile := "serviceAccountKey.json"
	if _, err := os.Stat(credFile); os.IsNotExist(err) {
		log.Println("⚠️ FCM: serviceAccountKey.json not found in root. Push notifications disabled.")
		return nil
	}

	// 2. Initialize Firebase App
	opt := option.WithCredentialsFile(credFile)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		log.Printf("⚠️ FCM: Error initializing app: %v", err)
		return nil
	}

	// 3. Get Messaging Client
	client, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("⚠️ FCM: Error getting messaging client: %v", err)
		return nil
	}

	log.Println("✅ FCM Push Service Initialized (serviceAccountKey.json)")
	return &PushService{
		client: client,
		app:    app,
	}
}

// 3. Worker Function (Call this in main.go)
func (ps *PushService) StartWorker() {
	log.Println("🚀 Notification Worker Started")
	for msg := range pushQueue {
		// Construct FCM Message
		message := &messaging.Message{
			Notification: &messaging.Notification{
				Title: msg.Title,
				Body:  msg.Body,
			},
			Data:  msg.Data,
			Topic: msg.Topic,
		}

		// Send Synchronously (Worker manages throughput)
		response, err := ps.client.Send(context.Background(), message)
		if err != nil {
			log.Printf("⚠️ FCM Send Error: %v", err)
		} else {
			log.Printf("📲 Push Sent: %s (MSG ID: %s)", msg.Body, response)
		}
	}
}

// SendWhaleAlert sends a push notification for significant whale movements
func (ps *PushService) SendWhaleAlert(alert Alert) {
	if ps == nil || ps.client == nil {
		return
	}

	// Safety Check: Double verify this is a Mega Whale (Level 5)
	if alert.Level < 5 {
		return
	}

	// Format Values
	var valueStr string
	if alert.FormattedValue != "" {
		valueStr = alert.FormattedValue
	} else {
		if alert.Data.Notional >= 1000000 {
			valueStr = fmt.Sprintf("$%.1fM", alert.Data.Notional/1000000)
		} else {
			valueStr = fmt.Sprintf("$%.0fK", alert.Data.Notional/1000)
		}
	}

	// Non-Blocking: Drop into channel
	select {
	case pushQueue <- PushMessage{
		Topic: "ALL_WHALES",
		Title: "🐋 Whale Alert",
		Body:  fmt.Sprintf("%s %s %s detected!", valueStr, alert.Symbol, alert.Data.Side),
		Data: map[string]string{
			"type":   alert.Type,
			"symbol": alert.Symbol,
			"value":  fmt.Sprintf("%.0f", alert.Data.Notional),
			"price":  fmt.Sprintf("%f", alert.Data.Price),
			"side":   alert.Data.Side,
		},
	}:
		// Successfully queued
	default:
		// Queue full, drop message to prevent blocking main thread
		log.Println("⚠️ Push Queue Full! Dropping alert.")
	}
}
