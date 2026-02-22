# Phase 12: Actors

Replace direct state store operations for inventory with Dapr virtual actors. Each product becomes a `ProductActor` in catalog-service (Go) that manages its own stock with turn-based concurrency — no more race conditions between competing orders.

> **Note**: Phase 12 layers on top of the existing deployment. It does not add new Kubernetes manifests — actor support is built into Dapr. Prerequisite: Phase 11 (which implies Phases 6-10 deployed on AKS).

**Teaching Points:**
- "Each product is a virtual actor that processes one stock operation at a time — race conditions eliminated, no distributed locks."
- "The workflow-service (.NET) invokes Go-hosted actors via the Dapr placement service — cross-language actor invocation."
- "Creating a product via REST automatically initializes its actor. The same state store backs both CRUD and actors."

## Prerequisites

- AKS cluster running with Phases 6-11 deployed
- Docker images rebuilt for catalog-service and workflow-service (code changes in both)
- `actorStateStore: "true"` on the statestore component (already set in all phases)
- Dapr placement service running (deployed automatically with Dapr on K8s)

### Docker Image Update

Both catalog-service and workflow-service have code changes. Rebuild and push:

```bash
cd /path/to/dapr_demo
docker build -t <your-dockerhub>/dapr-catalog-service:latest services/catalog-service
docker push <your-dockerhub>/dapr-catalog-service:latest

docker build -t <your-dockerhub>/dapr-workflow-service:latest services/workflow-service
docker push <your-dockerhub>/dapr-workflow-service:latest
```

Or use the existing `build-and-push.sh` from Phase 8.

## Quick Start

```bash
cd deployments/kubernetes-phase12-actors

# Deploy actor-enabled services on top of existing cluster
./scripts/deploy-actors.sh

# Verify
./scripts/test-actors.sh
```

## What Phase 12 Changes

### No New Manifests

Actor support requires no additional Kubernetes resources. The Dapr sidecar reads the actor configuration from the service's `/dapr/config` endpoint and registers with the placement service automatically. The existing statestore component (with `actorStateStore: "true"`) stores actor state using a separate key namespace.

### Service Code Changes

| Service | File | Change |
|---------|------|--------|
| catalog-service | `main.go` | Migrated from Gorilla Mux to chi router; uses `daprd.NewServiceWithMux()` for actor support; syncs actor stock on product create/update |
| catalog-service | `actor.go` (new) | ProductActor with Reserve, Release, GetStock, InitStock methods |
| catalog-service | `go.mod` | Replaced `gorilla/mux` with `go-chi/chi/v5` |
| workflow-service | `ReserveInventoryActivity.cs` | Uses `ActorProxy` to invoke ProductActor.Reserve instead of HTTP GET+PUT |
| workflow-service | `ReleaseInventoryActivity.cs` | Uses `ActorProxy` to invoke ProductActor.Release instead of HTTP GET+PUT |
| workflow-service | `OrderModels.cs` | Added actor request/response records |
| workflow-service | `WorkflowService.csproj` | Added `Dapr.Actors` NuGet package |

### ProductActor Methods

| Method | Input | Output | Purpose |
|--------|-------|--------|---------|
| `Reserve` | `{quantity: int}` | `{success, message, remainingStock}` | Decrement stock atomically |
| `Release` | `{quantity: int}` | `{success, message, remainingStock}` | Increment stock (compensation) |
| `GetStock` | `{}` | `{stock: int}` | Query current stock |
| `InitStock` | `{stock: int}` | `{stock: int}` | Set initial stock |

### How the Workflow Uses Actors

**Before (Phases 5-11):**
1. `ReserveInventoryActivity` → `GET /products/{id}` (read stock) → `PUT /products/{id}` (decrement stock)
2. Two concurrent orders could both read stock=10, both decrement, and oversell

**After (Phase 12):**
1. `ReserveInventoryActivity` → `GET /products/{id}` (metadata only) → `ActorProxy.Reserve(quantity)` (atomic)
2. The actor processes one request at a time — no race conditions

## Demo Walkthrough

### Demo: Actor Concurrency

```bash
./scripts/demo-actor-concurrency.sh
```

1. Create a product with 10 units of stock
2. Fire TWO concurrent reservations for 8 units each
3. Actor processes them sequentially (turn-based)
4. First succeeds (stock: 10 → 2), second fails (insufficient stock)
5. Stock never goes negative

## Files

| File | Purpose |
|------|---------|
| `scripts/deploy-actors.sh` | Verifies prerequisites, restarts updated services |
| `scripts/test-actors.sh` | Automated actor verification (registration, stock ops, workflow) |
| `scripts/demo-actor-concurrency.sh` | Interactive concurrency demo |

## Troubleshooting

### Actor not registering

Check the catalog-service sidecar logs for actor registration:

```bash
kubectl logs deployment/catalog-service -c daprd -n dapr-demo | grep -i actor
```

Verify the `/dapr/config` endpoint returns the actor type:

```bash
kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- http://localhost:3500/v1.0/metadata | python3 -m json.tool
```

### Placement service not running

The placement service is deployed automatically when Dapr is installed on Kubernetes:

```bash
kubectl get pods -n dapr-system -l app=dapr-placement-server
```

If missing, reinstall Dapr:

```bash
dapr init -k
```

### Actor state not persisting

Verify the statestore component has actor support enabled:

```bash
kubectl get component statestore -n dapr-demo -o yaml | grep actorStateStore
```

Actor state keys are namespaced differently from regular state keys: `catalog-service||ProductActorType||{actorId}||stock` vs `catalog-service||{productId}`.

### Workflow fails with actor invocation error

Verify the `Dapr.Actors` NuGet package is included and the workflow-service image was rebuilt:

```bash
kubectl logs deployment/workflow-service -n dapr-demo | grep -i actor
```

## What We're Not Doing

| Item | Why |
|------|-----|
| Actor reminders/timers | Adds complexity without a clear teaching payoff for inventory |
| Actor reentrancy | Not needed — stock operations are simple and don't call other actors |
| Multiple actor types | One type (ProductActor) is sufficient to demonstrate the pattern |
| Actor-based CRUD | Product metadata stays in regular state store; only stock moves to actors |
