package services

import (
	"context"
	"log"
	"net/http"
	"strings"

	firebase "firebase.google.com/go"
	"google.golang.org/api/option"
)

// User represents an authenticated user from Firebase
type User struct {
	UID           string
	Email         string
	EmailVerified bool
	DisplayName   string
	PhotoURL      string
}

// Global Firebase App (Init once in main)
var FirebaseApp *firebase.App

// InitFirebase initializes the Firebase Admin SDK
func InitFirebase(credentialsFile string) error {
	opt := option.WithCredentialsFile(credentialsFile)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		return err
	}
	FirebaseApp = app
	return nil
}

// Authentication Middleware
func AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Missing Authorization Header", http.StatusUnauthorized)
			return
		}

		tokenString := strings.Replace(authHeader, "Bearer ", "", 1)

		client, err := FirebaseApp.Auth(context.Background())
		if err != nil {
			log.Printf("Firebase Auth Client Error: %v", err)
			http.Error(w, "Internal Auth Error", http.StatusInternalServerError)
			return
		}

		token, err := client.VerifyIDToken(context.Background(), tokenString)
		if err != nil {
			log.Printf("Invalid Token: %v", err)
			http.Error(w, "Invalid Token", http.StatusUnauthorized)
			return
		}

		// Create User context
		user := &User{
			UID: token.UID,
		}
		if email, ok := token.Claims["email"].(string); ok {
			user.Email = email
		}
		// Add user to context logic here if needed (e.g., context.WithValue)

		next.ServeHTTP(w, r)
	})
}
