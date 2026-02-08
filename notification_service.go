package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

const chatIDFile = "chat_id.txt"

// NotificationService handles sending alerts to Telegram
type NotificationService struct {
	bot    *tgbotapi.BotAPI
	chatID int64

	// Pending Approvals
	pendingSignals sync.Map // Map[string]Signal (Key: SignalID/CallbackData)
}

// NewNotificationService initializes the Telegram bot
func NewNotificationService() *NotificationService {
	token := os.Getenv("TELEGRAM_BOT_TOKEN")
	if token == "" {
		log.Println("⚠️ TELEGRAM_BOT_TOKEN not found. Notifications disabled.")
		return nil
	}

	bot, err := tgbotapi.NewBotAPI(token)
	if err != nil {
		log.Printf("⚠️ Failed to init Telegram Bot: %v", err)
		return nil
	}

	log.Printf("✅ Authorized on account %s", bot.Self.UserName)

	// User Chat ID (Optional - if not set, we can sniff it from updates)
	chatIDStr := os.Getenv("TELEGRAM_CHAT_ID")
	var chatID int64
	if chatIDStr != "" {
		chatID, _ = strconv.ParseInt(chatIDStr, 10, 64)
	}

	ns := &NotificationService{
		bot:    bot,
		chatID: chatID,
	}

	// If no Chat ID, try loading from file
	if chatID == 0 {
		chatID = ns.loadChatID()
		ns.chatID = chatID
	}

	if chatID != 0 {
		log.Printf("✅ Loaded Persistent Chat ID: %d", chatID)
	}

	// If no Chat ID, start listener to grab it (Logic moved to main to allow Callback injection)
	// We no longer start it automatically here because we need the callback.

	return ns
}

// loadChatID reads the saved ID from file
func (ns *NotificationService) loadChatID() int64 {
	data, err := ioutil.ReadFile(chatIDFile)
	if err != nil {
		return 0
	}

	id, err := strconv.ParseInt(string(data), 10, 64)
	if err != nil {
		return 0
	}
	return id
}

// saveChatID writes ID to file
func (ns *NotificationService) saveChatID(id int64) {
	err := ioutil.WriteFile(chatIDFile, []byte(fmt.Sprintf("%d", id)), 0644)
	if err != nil {
		log.Printf("⚠️ Failed to save Chat ID: %v", err)
	} else {
		log.Println("💾 Chat ID Saved Persistently.")
	}
}

// StartEventListener polls updates for commands and callbacks
func (ns *NotificationService) StartEventListener(statusCallback func() string, approvalCallback func(interface{}), stopCallback func(), reportCallback func() string) {
	log.Println("📢 TELEGRAM: Listening for events...")
	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60

	updates := ns.bot.GetUpdatesChan(u)

	for update := range updates {
		// A. Handle Callbacks (Buttons)
		if update.CallbackQuery != nil {
			data := update.CallbackQuery.Data

			// 1. EXECUTE
			if strings.HasPrefix(data, "EXECUTE_") {
				sigID := strings.TrimPrefix(data, "EXECUTE_")
				if val, ok := ns.pendingSignals.Load(sigID); ok {
					ns.bot.Send(tgbotapi.NewCallback(update.CallbackQuery.ID, "🚀 Executing..."))
					ns.Notify("✅ **APPROVAL RECEIVED**. Executing Trade!")
					approvalCallback(val) // Execute
					ns.pendingSignals.Delete(sigID)
				} else {
					ns.bot.Send(tgbotapi.NewCallback(update.CallbackQuery.ID, "⚠️ Expired"))
				}
			}

			// 2. DISCARD
			if strings.HasPrefix(data, "DISCARD_") {
				sigID := strings.TrimPrefix(data, "DISCARD_")
				ns.bot.Send(tgbotapi.NewCallback(update.CallbackQuery.ID, "🗑️ Discarded"))
				ns.pendingSignals.Delete(sigID)
				// Delete the message
				del := tgbotapi.NewDeleteMessage(update.CallbackQuery.Message.Chat.ID, update.CallbackQuery.Message.MessageID)
				ns.bot.Send(del)
			}
			continue
		}

		if update.Message == nil {
			continue
		}

		// B. Auto-Configure Chat ID
		if ns.chatID == 0 {
			ns.chatID = update.Message.Chat.ID
			log.Printf("✅ TELEGRAM CHAT ID DETECTED: %d", ns.chatID)
			ns.Notify("🔔 Bot Connected! Notifications enabled.")
		}

		// C. Handle Commands
		if update.Message.IsCommand() {
			switch update.Message.Command() {
			case "status":
				if statusCallback != nil {
					report := statusCallback()
					ns.Notify(report)
				}
			case "start":
				// Capture ID if needed
				if ns.chatID == 0 || ns.chatID != update.Message.Chat.ID {
					ns.chatID = update.Message.Chat.ID
					ns.saveChatID(ns.chatID)
					log.Printf("✅ TELEGRAM CHAT ID CAPTURED & SAVED: %d", ns.chatID)
				}
				ns.Notify("🚀 *Connection established!*\nI am now monitoring your Whale Signals for Dubai.\nCurrent PnL: $0.00.")
			case "stop":
				ns.Notify("🛑 **EMERGENCY STOP TRIGGERED**\nCancelling Orders...\nClosing Positions...\nShutting Down.")
				if stopCallback != nil {
					stopCallback()
				}
			case "report":
				if reportCallback != nil {
					report := reportCallback()
					ns.Notify(report)
				}
			}
		}
	}
}

// SendApprovalRequest sends an interactive alert
func (ns *NotificationService) SendApprovalRequest(signal interface{}) {
	if ns.chatID == 0 {
		return
	}

	// Convert interface back to Signal struct (Assuming we pass Signal struct)
	// We use reflection or just assume caller passes right type.
	// For simplicity, let's assume we pass a formatted string ID and keep the object in memory.
	// Actually, we need to map a unique ID to this signal.

	// Generate ID
	sigID := fmt.Sprintf("%d", time.Now().UnixNano())
	ns.pendingSignals.Store(sigID, signal)

	// Create Message
	// We need the Signal details. Since 'Signal' type isn't defined in this package,
	// we will rely on the caller to format the text? No, user wants specific format.
	// We will assume 'signal' is of type Signal. But circular import risk if main/signal defines it?
	// Signal struct is in execution_service.go (which is package main). Access is fine.

	// Cast
	sig, ok := signal.(Signal)
	if !ok {
		return
	}

	// Determine Momentum Icon & RSI Warning
	momIcon := sig.Label
	rsiWarning := ""

	// RSI Check (75/25)

	// RSI Check (75/25)
	if sig.Side == "LONG" && sig.RSI > 75 {
		rsiWarning = " ⚠️ EXTENDED"
	}
	if sig.Side == "SHORT" && sig.RSI < 25 {
		rsiWarning = " ⚠️ EXTENDED"
	}

	msg := tgbotapi.NewMessage(ns.chatID, fmt.Sprintf("🔔 **INSTITUTIONAL SENTINEL ALERT**\n\n**Pair:** %s | **Type:** %s\n**Trend (1H/15M):** %s | %s\n**Label:** %s\n**RSI:** %.0f%s\n**Confidence:** %.1f Whales + CVD Confirmed 🐳\n**Targets:** Entry (Maker) | TP: 3:1 ($%.4f) | SL: $50 Risk ($%.4f)",
		sig.Symbol, sig.Side, sig.Trend1H, sig.Trend15M, momIcon, sig.RSI, rsiWarning, sig.Score, sig.Target, sig.StopLoss))
	msg.ParseMode = "Markdown"

	// Buttons
	keyboard := tgbotapi.NewInlineKeyboardMarkup(
		tgbotapi.NewInlineKeyboardRow(
			tgbotapi.NewInlineKeyboardButtonData("✅ EXECUTE", "EXECUTE_"+sigID),
			tgbotapi.NewInlineKeyboardButtonData("❌ DISCARD", "DISCARD_"+sigID),
		),
	)
	msg.ReplyMarkup = keyboard

	_, err := ns.bot.Send(msg)
	if err != nil {
		log.Printf("⚠️ Failed to send approval request: %v", err)
	}
}

// Notify sends a message asynchronously
func (ns *NotificationService) Notify(msg string) {
	if ns == nil || ns.bot == nil || ns.chatID == 0 {
		return
	}

	// Fire and forget
	go func() {
		msgConfig := tgbotapi.NewMessage(ns.chatID, msg)
		msgConfig.ParseMode = "Markdown"
		_, err := ns.bot.Send(msgConfig)
		if err != nil {
			log.Printf("⚠️ Failed to send Telegram: %v", err)
		}
	}()
}

// SendAppPush simulates sending a push to the Mobile App Backend
func (ns *NotificationService) SendAppPush(sig PublicSignal) {
	// In production, this would make an HTTP POST to Firebase/backend
	// For now, we log it clearly so we can verify flow
	log.Printf("🚀 [APP PUSH] %s %s | Stars: %d | Entry: %s | Vol: %s",
		sig.Direction, sig.Symbol, sig.Stars, sig.EntryZone, sig.Volatility)

	// Optional: Send a "Shadow" Telegram Message to a separate Admin Channel if we had one
	// ns.Notify(fmt.Sprintf("📱 **APP PUSH**: %s %s (%d Stars)", sig.Direction, sig.Symbol, sig.Stars))
}
