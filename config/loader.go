package config

import (
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config holds the application configuration
type Config struct {
	BinanceAPIKey      string
	BinanceAPISecret   string
	IsTestnet          bool
	MaxExposure        float64
	MaxConcurrent      int
	Leverage           int
	TotalNotionalLimit float64
}

// LoadConfig loads variables from .env and returns a Config struct
func LoadConfig() *Config {
	err := godotenv.Load()
	if err != nil {
		log.Println("⚠️  Warning: .env file not found. Relying on system environment variables.")
	}

	apiKey := os.Getenv("BINANCE_API_KEY")
	apiSecret := os.Getenv("BINANCE_API_SECRET")
	if apiSecret == "" {
		apiSecret = os.Getenv("BINANCE_SECRET_KEY")
	}

	if apiKey == "" || apiSecret == "" {
		log.Println("⚠️  CRITICAL: Binance Credentials missing!")
	}

	// Parse Max Exposure
	maxExpStr := os.Getenv("MAX_EXPOSURE")
	maxExp := 0.20
	if maxExpStr != "" {
		if val, err := strconv.ParseFloat(maxExpStr, 64); err == nil {
			maxExp = val
		}
	}

	// Parse Max Concurrent Trades
	maxConcStr := os.Getenv("MAX_CONCURRENT_TRADES")
	maxConc := 3
	if maxConcStr != "" {
		if val, err := strconv.Atoi(maxConcStr); err == nil {
			maxConc = val
		}
	}

	// Parse Leverage
	levStr := os.Getenv("LEVERAGE")
	leverage := 20 // Default
	if levStr != "" {
		if val, err := strconv.Atoi(levStr); err == nil {
			leverage = val
		}
	}

	// Parse Total Notional Limit
	tnlStr := os.Getenv("TOTAL_NOTIONAL_LIMIT")
	totalLimit := 2000.0 // Default
	if tnlStr != "" {
		if val, err := strconv.ParseFloat(tnlStr, 64); err == nil {
			totalLimit = val
		}
	}

	return &Config{
		BinanceAPIKey:      apiKey,
		BinanceAPISecret:   apiSecret,
		IsTestnet:          false, // Default to production for "Predator" unless specified
		MaxExposure:        maxExp,
		MaxConcurrent:      maxConc,
		Leverage:           leverage,
		TotalNotionalLimit: totalLimit,
	}
}
