package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/gorilla/mux"
)

const (
	stateStoreName = "statestore"
	port           = "8080"
)

type Product struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	Stock       int     `json:"stock"`
}

var daprClient dapr.Client

func main() {
	// Initialize Dapr client
	client, err := dapr.NewClient()
	if err != nil {
		log.Fatalf("Failed to create Dapr client: %v", err)
	}
	defer client.Close()
	daprClient = client

	log.Println("Dapr client initialized successfully")

	// Setup HTTP router
	r := mux.NewRouter()

	// Product endpoints
	r.HandleFunc("/products", getProducts).Methods("GET")
	r.HandleFunc("/products/{id}", getProduct).Methods("GET")
	r.HandleFunc("/products", createProduct).Methods("POST")
	r.HandleFunc("/products/{id}", updateProduct).Methods("PUT")
	r.HandleFunc("/products/{id}", deleteProduct).Methods("DELETE")

	// Health check
	r.HandleFunc("/health", healthCheck).Methods("GET")

	log.Printf("Catalog Service listening on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func healthCheck(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func getProducts(w http.ResponseWriter, r *http.Request) {
	// In a real app, you'd store a list of product IDs
	// For demo purposes, we'll return a simple message
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Use GET /products/{id} to retrieve a specific product",
	})
}

func getProduct(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	productID := vars["id"]

	ctx := context.Background()

	// Get product from Dapr state store
	item, err := daprClient.GetState(ctx, stateStoreName, productID, nil)
	if err != nil {
		log.Printf("Error getting product: %v", err)
		http.Error(w, "Error retrieving product", http.StatusInternalServerError)
		return
	}

	if item.Value == nil {
		http.Error(w, "Product not found", http.StatusNotFound)
		return
	}

	var product Product
	if err := json.Unmarshal(item.Value, &product); err != nil {
		log.Printf("Error unmarshaling product: %v", err)
		http.Error(w, "Error parsing product", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(product)
}

func createProduct(w http.ResponseWriter, r *http.Request) {
	var product Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if product.ID == "" {
		http.Error(w, "Product ID is required", http.StatusBadRequest)
		return
	}

	ctx := context.Background()

	// Save product to Dapr state store
	productJSON, err := json.Marshal(product)
	if err != nil {
		log.Printf("Error marshaling product: %v", err)
		http.Error(w, "Error saving product", http.StatusInternalServerError)
		return
	}

	if err := daprClient.SaveState(ctx, stateStoreName, product.ID, productJSON, nil); err != nil {
		log.Printf("Error saving product: %v", err)
		http.Error(w, "Error saving product", http.StatusInternalServerError)
		return
	}

	log.Printf("Product created: %s", product.ID)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(product)
}

func updateProduct(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	productID := vars["id"]

	var product Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	product.ID = productID
	ctx := context.Background()

	// Save updated product to Dapr state store
	productJSON, err := json.Marshal(product)
	if err != nil {
		log.Printf("Error marshaling product: %v", err)
		http.Error(w, "Error updating product", http.StatusInternalServerError)
		return
	}

	if err := daprClient.SaveState(ctx, stateStoreName, product.ID, productJSON, nil); err != nil {
		log.Printf("Error updating product: %v", err)
		http.Error(w, "Error updating product", http.StatusInternalServerError)
		return
	}

	log.Printf("Product updated: %s", product.ID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(product)
}

func deleteProduct(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	productID := vars["id"]

	ctx := context.Background()

	// Delete product from Dapr state store
	if err := daprClient.DeleteState(ctx, stateStoreName, productID, nil); err != nil {
		log.Printf("Error deleting product: %v", err)
		http.Error(w, "Error deleting product", http.StatusInternalServerError)
		return
	}

	log.Printf("Product deleted: %s", productID)
	w.WriteHeader(http.StatusNoContent)
}
