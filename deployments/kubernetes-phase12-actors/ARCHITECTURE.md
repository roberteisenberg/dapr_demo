# Phase 12: Actors Architecture

## Overview

Phase 12 introduces Dapr virtual actors for inventory management. Each product becomes a `ProductActor` instance in catalog-service (Go). The actor manages stock with turn-based concurrency — no distributed locks, no race conditions. The workflow-service (.NET) invokes Go-hosted actors via the Dapr placement service.

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Actor-Based Inventory Flow                         │
│                                                                      │
│  REST API (Product CRUD)                Actor System                 │
│  ┌────────────────────────┐             ┌──────────────────────┐    │
│  │ POST /products         │──(create)──▶│ InitStock(stock)     │    │
│  │ PUT  /products/{id}    │──(update)──▶│                      │    │
│  │ GET  /products/{id}    │             │  ProductActor         │    │
│  │ GET  /products         │             │  ┌────────────────┐  │    │
│  │ DELETE /products/{id}  │             │  │ stock: int     │  │    │
│  └────────────────────────┘             │  └────────────────┘  │    │
│                                          │                      │    │
│  Workflow (Order Saga)                   │  Reserve(qty)        │    │
│  ┌────────────────────────┐             │  Release(qty)        │    │
│  │ ReserveInventory       │──(actor)───▶│  GetStock()          │    │
│  │ ReleaseInventory       │──(actor)───▶│  InitStock(stock)    │    │
│  │ (+ GET for metadata)   │             └──────────────────────┘    │
│  └────────────────────────┘                                          │
│                                                                      │
│  State Store (Redis)                                                 │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │ Regular keys:  catalog-service||{productId}        (CRUD)  │     │
│  │ Actor keys:    catalog-service||ProductActorType||          │     │
│  │                {productId}||stock                  (Actor)  │     │
│  └────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

## 1. Why Actors for Inventory

### The Race Condition Problem

In Phases 5-11, `ReserveInventoryActivity` does:
1. `GET /products/{id}` → reads stock (e.g., 10)
2. Calculates `newStock = stock - quantity` (e.g., 10 - 8 = 2)
3. `PUT /products/{id}` → writes stock = 2

Two concurrent orders for the same product:
```
Order A: GET stock → 10        Order B: GET stock → 10
Order A: 10 - 8 = 2           Order B: 10 - 8 = 2
Order A: PUT stock = 2         Order B: PUT stock = 2
```

Both orders succeed, but only 2 units remain — the product was oversold by 6 units.

### The Actor Solution

With a ProductActor, stock operations are serialized:
```
Order A: Reserve(8) → actor locks → reads 10 → writes 2 → returns success
Order B: Reserve(8) → waits for lock → reads 2 → insufficient stock → returns failure
```

Turn-based concurrency means at most one method executes at a time per actor instance. No distributed locks needed — the Dapr runtime enforces this.

## 2. Actor Lifecycle

### Activation and Deactivation

```
Product Created via REST API
        │
        ▼
syncActorStock() ──────▶ Dapr sidecar ──▶ Placement service
        │                                         │
        │                               Routes to catalog-service
        │                                         │
        ▼                                         ▼
State store: product data            Actor activated (ProductActorFactory)
(regular key)                        Actor state: {stock: N}
                                     (actor key namespace)
                                              │
                                     (idle for 60 min)
                                              │
                                              ▼
                                     Actor deactivated
                                     (state persists in store)
                                              │
                                     (next invocation)
                                              │
                                              ▼
                                     Actor reactivated
                                     (state loaded from store)
```

Actors are **virtual**: they don't consume memory when idle. The Dapr runtime deactivates them after the idle timeout (default 60 minutes) and reactivates them on the next invocation, loading state from the store.

### Placement Service

The Dapr placement service maintains a mapping of actor types to services:

| Actor Type | Host Service | Instances |
|-----------|-------------|-----------|
| `ProductActorType` | `catalog-service` | One per product ID |

When `workflow-service` invokes `ActorProxy.Create(actorId, "ProductActorType")`, its local Dapr sidecar queries the placement service to find which `catalog-service` pod should handle that actor. If multiple catalog-service replicas exist (HPA from Phase 11), the placement service distributes actors across them.

## 3. Gorilla Mux → Chi Migration

### Why

The Dapr Go SDK's HTTP service (`daprd.NewServiceWithMux()`) requires a chi router. It registers internal routes for actor support:

| Route | Purpose |
|-------|---------|
| `GET /dapr/config` | Returns registered actor types and configuration |
| `PUT /actors/{type}/{id}/method/{method}` | Actor method invocation |
| `DELETE /actors/{type}/{id}` | Actor deactivation |

These routes coexist with the existing CRUD endpoints on the same chi router.

### What Changed

| Before (Gorilla Mux) | After (Chi) |
|----------------------|-------------|
| `mux.NewRouter()` | `chi.NewRouter()` |
| `r.HandleFunc("/path", h).Methods("GET")` | `r.Get("/path", h)` |
| `mux.Vars(r)["id"]` | `chi.URLParam(r, "id")` |
| `http.ListenAndServe(":8080", r)` | `daprd.NewServiceWithMux(":8080", r).Start()` |

The CRUD handler logic is unchanged — only the router and URL parameter extraction changed.

## 4. Cross-Service Actor Invocation

The workflow-service (.NET) invokes Go-hosted actors without a shared interface:

```csharp
// .NET workflow activity
var actorId = new ActorId(input.ProductId);
var proxy = ActorProxy.Create(actorId, "ProductActorType");
var result = await proxy.InvokeMethodAsync<ActorReserveRequest, ActorReserveResponse>(
    "Reserve", new ActorReserveRequest(input.Quantity));
```

Under the hood:
1. .NET Dapr sidecar sends `PUT /v1.0/actors/ProductActorType/{id}/method/Reserve` to localhost:3500
2. Sidecar queries placement service → finds `catalog-service`
3. Request routed to catalog-service's Dapr sidecar
4. Sidecar invokes the Go actor method
5. JSON response returned through the chain

No shared assembly, no code generation, no protobuf — just JSON over HTTP via the Dapr actor API.

## 5. State Isolation

Actor state and regular state coexist in the same Redis instance but use different key namespaces:

| Key Pattern | Example | Source |
|-------------|---------|--------|
| `{appId}\|\|{key}` | `catalog-service\|\|widget-001` | Regular state (CRUD) |
| `{appId}\|\|{actorType}\|\|{actorId}\|\|{stateKey}` | `catalog-service\|\|ProductActorType\|\|widget-001\|\|stock` | Actor state |

This means:
- Existing product data (name, price, description, category) stays in regular state
- Actor manages only the `stock` integer
- Both share the same Redis connection pool
- No migration needed for existing data

## 6. Stock Synchronization

When a product is created or updated via the REST API, `syncActorStock()` initializes the actor's stock:

```
POST /products {id: "widget", stock: 100}
        │
        ├── 1. Save to state store (regular key)
        │
        └── 2. PUT /v1.0/actors/ProductActorType/widget/method/InitStock
                  body: {stock: 100}
                  │
                  └── Actor state: stock = 100
```

This ensures the actor always has the correct stock count, even for products created before Phase 12 was deployed (just re-create them).

## Design Decisions

### Actor Manages Stock Only

The actor stores a single integer (`stock`). Product metadata (name, price, description, category) stays in the regular state store. This minimizes the migration surface — existing CRUD endpoints and data formats are unchanged. The workflow activity still does a regular `GET /products/{id}` for metadata, then uses the actor for the concurrency-critical stock operation.

### No Shared Interface

Cross-service actor invocation uses untyped `ActorProxy` with JSON serialization. Defining a shared interface (via NuGet package or protobuf) would create a coupling between the Go actor host and .NET caller. The untyped approach is simpler and demonstrates that Dapr actors are language-agnostic.

### syncActorStock via HTTP

The `syncActorStock` function calls the Dapr sidecar's actor HTTP API rather than using the Go SDK's client stub pattern. This is intentional: the HTTP call is explicit about what's happening (calling the local sidecar), easy to debug (visible in logs and Zipkin), and doesn't require additional actor client boilerplate.

### No New Manifests

Unlike Phases 4-11 which add Kubernetes resources (components, configurations, HPAs), Phase 12 changes only service code. This teaches an important lesson: Dapr's actor infrastructure (placement service, state store) is already deployed — you just need to register actor types in your service code.
