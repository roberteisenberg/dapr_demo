package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/gorilla/mux"
)

const (
	stateStoreName  = "statestore"
	productIndexKey = "product-index"
	port            = "8080"
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
	// Initialize Dapr client with retries (sidecar starts asynchronously in Docker)
	var client dapr.Client
	var err error
	maxRetries := 10

	for i := 0; i < maxRetries; i++ {
		client, err = dapr.NewClient()
		if err == nil {
			break
		}
		log.Printf("Waiting for Dapr sidecar... (attempt %d/%d)", i+1, maxRetries)
		time.Sleep(2 * time.Second)
	}

	if err != nil {
		log.Fatalf("Failed to create Dapr client after %d attempts: %v", maxRetries, err)
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
	ctx := context.Background()

	// Get the product index (list of product IDs)
	indexItem, err := daprClient.GetState(ctx, stateStoreName, productIndexKey, nil)
	if err != nil {
		log.Printf("Error getting product index: %v", err)
		http.Error(w, "Error retrieving products", http.StatusInternalServerError)
		return
	}

	var productIDs []string
	if indexItem.Value != nil {
		if err := json.Unmarshal(indexItem.Value, &productIDs); err != nil {
			log.Printf("Error unmarshaling product index: %v", err)
			http.Error(w, "Error parsing product index", http.StatusInternalServerError)
			return
		}
	}

	// Fetch all products
	products := []Product{}
	for _, id := range productIDs {
		item, err := daprClient.GetState(ctx, stateStoreName, id, nil)
		if err != nil {
			log.Printf("Error getting product %s: %v", id, err)
			continue
		}

		if item.Value != nil {
			var product Product
			if err := json.Unmarshal(item.Value, &product); err != nil {
				log.Printf("Error unmarshaling product %s: %v", id, err)
				continue
			}
			products = append(products, product)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(products)
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

	// Update product index
	if err := addToProductIndex(ctx, product.ID); err != nil {
		log.Printf("Error updating product index: %v", err)
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

	// Update product index
	if err := removeFromProductIndex(ctx, productID); err != nil {
		log.Printf("Error updating product index: %v", err)
	}

	log.Printf("Product deleted: %s", productID)
	w.WriteHeader(http.StatusNoContent)
}

func addToProductIndex(ctx context.Context, productID string) error {
	indexItem, err := daprClient.GetState(ctx, stateStoreName, productIndexKey, nil)
	if err != nil {
		return err
	}

	var productIDs []string
	if indexItem.Value != nil {
		if err := json.Unmarshal(indexItem.Value, &productIDs); err != nil {
			return err
		}
	}

	for _, id := range productIDs {
		if id == productID {
			return nil
		}
	}

	productIDs = append(productIDs, productID)

	indexJSON, err := json.Marshal(productIDs)
	if err != nil {
		return err
	}

	return daprClient.SaveState(ctx, stateStoreName, productIndexKey, indexJSON, nil)
}

func removeFromProductIndex(ctx context.Context, productID string) error {
	indexItem, err := daprClient.GetState(ctx, stateStoreName, productIndexKey, nil)
	if err != nil {
		return err
	}

	var productIDs []string
	if indexItem.Value != nil {
		if err := json.Unmarshal(indexItem.Value, &productIDs); err != nil {
			return err
		}
	}

	newIDs := []string{}
	for _, id := range productIDs {
		if id != productID {
			newIDs = append(newIDs, id)
		}
	}

	indexJSON, err := json.Marshal(newIDs)
	if err != nil {
		return err
	}

	return daprClient.SaveState(ctx, stateStoreName, productIndexKey, indexJSON, nil)
}
