package main

import (
	"context"
	"fmt"
	"log"

	"github.com/dapr/go-sdk/actor"
)

const (
	actorType     = "ProductActorType"
	stockStateKey = "stock"
)

// ProductActor manages per-product stock with turn-based concurrency.
// Each product ID becomes an actor instance — no race conditions between
// competing Reserve/Release calls from concurrent orders.
type ProductActor struct {
	actor.ServerImplBaseCtx
}

func (a *ProductActor) Type() string {
	return actorType
}

// ReserveRequest is the input for a stock reservation.
type ReserveRequest struct {
	Quantity int `json:"quantity"`
}

// ReserveResponse is the result of a stock reservation attempt.
type ReserveResponse struct {
	Success        bool   `json:"success"`
	Message        string `json:"message"`
	RemainingStock int    `json:"remainingStock"`
}

// ReleaseRequest is the input for releasing reserved stock (compensation).
type ReleaseRequest struct {
	Quantity int `json:"quantity"`
}

// ReleaseResponse is the result of a stock release.
type ReleaseResponse struct {
	Success        bool   `json:"success"`
	Message        string `json:"message"`
	RemainingStock int    `json:"remainingStock"`
}

// StockResponse is the result of a stock query.
type StockResponse struct {
	Stock int `json:"stock"`
}

// Reserve decrements stock atomically. Returns failure if insufficient stock.
// Turn-based concurrency guarantees no two Reserve calls execute simultaneously
// for the same product — eliminating race conditions without distributed locks.
func (a *ProductActor) Reserve(ctx context.Context, req *ReserveRequest) (*ReserveResponse, error) {
	stock, err := a.getStock(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get stock: %w", err)
	}

	if stock < req.Quantity {
		log.Printf("Actor %s: insufficient stock for reservation: available=%d, requested=%d",
			a.ID(), stock, req.Quantity)
		return &ReserveResponse{
			Success:        false,
			Message:        fmt.Sprintf("Insufficient stock: available=%d, requested=%d", stock, req.Quantity),
			RemainingStock: stock,
		}, nil
	}

	newStock := stock - req.Quantity
	if err := a.GetStateManager().Set(ctx, stockStateKey, newStock); err != nil {
		return nil, fmt.Errorf("failed to save stock: %w", err)
	}

	log.Printf("Actor %s: reserved %d units. Stock: %d -> %d",
		a.ID(), req.Quantity, stock, newStock)

	return &ReserveResponse{
		Success:        true,
		Message:        "Inventory reserved successfully",
		RemainingStock: newStock,
	}, nil
}

// Release increments stock (compensation for failed orders).
func (a *ProductActor) Release(ctx context.Context, req *ReleaseRequest) (*ReleaseResponse, error) {
	stock, err := a.getStock(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get stock: %w", err)
	}

	newStock := stock + req.Quantity
	if err := a.GetStateManager().Set(ctx, stockStateKey, newStock); err != nil {
		return nil, fmt.Errorf("failed to save stock: %w", err)
	}

	log.Printf("Actor %s: released %d units. Stock: %d -> %d",
		a.ID(), req.Quantity, stock, newStock)

	return &ReleaseResponse{
		Success:        true,
		Message:        "Inventory released successfully",
		RemainingStock: newStock,
	}, nil
}

// GetStock returns the current stock for this product actor.
func (a *ProductActor) GetStock(ctx context.Context) (*StockResponse, error) {
	stock, err := a.getStock(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get stock: %w", err)
	}

	return &StockResponse{Stock: stock}, nil
}

// getStock reads the stock from actor state, returning 0 if not yet initialized.
func (a *ProductActor) getStock(ctx context.Context) (int, error) {
	exists, err := a.GetStateManager().Contains(ctx, stockStateKey)
	if err != nil {
		return 0, err
	}
	if !exists {
		return 0, nil
	}

	var stock int
	if err := a.GetStateManager().Get(ctx, stockStateKey, &stock); err != nil {
		return 0, err
	}
	return stock, nil
}

// InitStock sets the initial stock for this product actor.
// Called when a product is created or updated via the REST API.
func (a *ProductActor) InitStock(ctx context.Context, req *StockResponse) (*StockResponse, error) {
	if err := a.GetStateManager().Set(ctx, stockStateKey, req.Stock); err != nil {
		return nil, fmt.Errorf("failed to initialize stock: %w", err)
	}

	log.Printf("Actor %s: initialized stock to %d", a.ID(), req.Stock)
	return &StockResponse{Stock: req.Stock}, nil
}

// ProductActorFactory creates new ProductActor instances.
// Called by the Dapr runtime when an actor is activated.
func ProductActorFactory() actor.ServerContext {
	return &ProductActor{}
}
