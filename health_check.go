package main

import (
	"encoding/json"
	"net/http"
	"time"
)

// SimpleHealthCheck returns a 200 OK with a JSON status
func SimpleHealthCheck(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"time":   time.Now().Format(time.RFC3339),
	})
}
