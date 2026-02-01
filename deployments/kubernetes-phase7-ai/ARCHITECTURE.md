# AI Integration Architecture

## Overview

This phase introduces AI into the Dapr microservices demo in two ways:

1. **Phase 7 (Manual):** "Copy for AI" button exports catalog/order data for Claude Desktop
2. **Phase 7-A (Fraud Check):** An AI-powered fraud detection step in the order fulfillment workflow, using the Dapr Conversation API to call Claude

The key teaching point: an LLM call fits into a deterministic Dapr Workflow as a regular activity. The workflow stays deterministic (fixed step order), but one step uses AI for analysis.

## Updated Order Fulfillment Workflow (Phase 7-A)

```
Before (Phase 5 — 4 steps):           After (Phase 7-A — 5 steps):

1. Validate Order                      1. Validate Order
2. Reserve Inventory                   2. Reserve Inventory
3. Process Payment                     3. Check Fraud (NEW — calls Claude)
4. Notify Customer                        ↳ if flagged: compensate, reject
                                       4. Process Payment
                                       5. Notify Customer
```

The fraud check uses the Dapr Conversation API (`conversation.anthropic` component) to ask Claude to assess order risk. The workflow-service container never sees the API key — it goes through the Dapr sidecar.

### Fraud Check Flow

```
OrderFulfillmentWorkflow (C#/.NET Dapr Workflow)
  │
  ├─ Step 1: ValidateOrderActivity
  ├─ Step 2: ReserveInventoryActivity
  │
  ├─ Step 3: CheckFraudActivity (NEW)
  │    │
  │    │  Build prompt with order details
  │    │  (customer, product, quantity, total)
  │    │
  │    │  POST http://localhost:3500/v1.0-alpha1/conversation/anthropic-llm/converse
  │    │  { "inputs": [{ "content": prompt }] }
  │    │        │
  │    │        ▼
  │    │  Dapr sidecar → conversation.anthropic → Claude API
  │    │        │
  │    │        ▼
  │    │  Parse response: { approved, riskLevel, reasoning }
  │    │
  │    ├─ approved=true  → continue to payment
  │    └─ approved=false → ReleaseInventoryActivity (compensation) → reject order
  │
  ├─ Step 4: ProcessPaymentActivity
  └─ Step 5: NotifyCustomerActivity
```

### Graceful Degradation

If the Conversation API is unavailable (no API key, service error, timeout), the fraud check **approves by default** with `riskLevel: "unknown"`. This means:

- The workflow never blocks on AI failures
- Orders still flow through without the API key configured
- Logs indicate when the fraud check was skipped

## Network Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster (minikube)                    │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                     dapr-demo namespace                       ││
│  │                                                               ││
│  │   ┌─────────────────┐                                        ││
│  │   │  NGINX Ingress  │ ◄── External traffic (:8080)           ││
│  │   │  + Dapr sidecar │                                        ││
│  │   └────────┬────────┘                                        ││
│  │            │                                                  ││
│  │  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌──────────────────┐ ││
│  │  │ catalog │ │  order  │ │ notifica-│ │ workflow-service  │ ││
│  │  │ service │ │ service │ │   tion   │ │ + CheckFraudAct. │ ││
│  │  │ + daprd │ │ + daprd │ │ + daprd  │ │ + daprd ──► Claude│ ││
│  │  └─────────┘ └─────────┘ └──────────┘ └──────────────────┘ ││
│  │                                                               ││
│  │  ┌───────┐ ┌───────┐ ┌────────────────────┐                ││
│  │  │ Redis │ │Zipkin │ │ web-app (no sidecar)│                ││
│  │  └───────┘ └───────┘ └────────────────────┘                ││
│  └──────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

## What Changed from Phase 5

### Workflow-Service Changes

| File | Change |
|------|--------|
| `Activities/CheckFraudActivity.cs` | New — calls Dapr Conversation API via HTTP |
| `Models/OrderModels.cs` | Added `FraudCheckResult` record |
| `Workflows/OrderFulfillmentWorkflow.cs` | Inserted fraud check between reserve and payment |
| `Program.cs` | Registered `CheckFraudActivity`, added `IHttpClientFactory` |

### Dapr Conversation API

The `conversation.anthropic` component abstracts the LLM provider. The workflow-service calls it through the Dapr sidecar:

```
POST http://localhost:{DAPR_HTTP_PORT}/v1.0-alpha1/conversation/anthropic-llm/converse
{
  "inputs": [{ "content": "Analyze this order for fraud risk: ..." }]
}
```

Response:
```json
{
  "outputs": [{ "result": "{\"approved\": true, \"riskLevel\": \"low\", \"reasoning\": \"...\"}" }]
}
```

The .NET Dapr SDK doesn't have a native Conversation API client yet, so CheckFraudActivity uses `IHttpClientFactory` to make the HTTP call directly.

### Dapr Components

One new component (in `03-components/`):

| Component | Type | Purpose |
|-----------|------|---------|
| `anthropic-llm` | `conversation.anthropic` | LLM calls via Dapr Conversation API |

Scoped to `workflow-service`.

### Order List Endpoint

The order-service gains a `GET /orders` endpoint that returns all orders. This is backed by an order index maintained in the Dapr state store:

```
POST /orders (create order)
  └─ Save order to state store (key: orderId)
  └─ Append orderId to order index (key: order-index)
  └─ Publish event to pub/sub

GET /orders (list all)
  └─ Read order index from state store
  └─ Read each order by ID
  └─ Return array
```

### Frontend Changes

- **"Copy for AI" button** — Exports catalog + order data as a structured prompt
- **5-step saga display** — Updated from 4 steps to show "Check Fraud" between Reserve and Payment
- **Fraud failure handling** — UI shows fraud reasoning when an order is flagged

## API Key Management

The Claude API key is provided via a Kubernetes secret:

```bash
kubectl create secret generic anthropic-api-key \
  --from-literal=api-key=$ANTHROPIC_API_KEY \
  -n dapr-demo
```

The `conversation.anthropic` component reads the key via `secretKeyRef` — the workflow-service container never sees it.

## Why a Workflow Activity, Not a Separate Service?

The fraud check is a single LLM call inside a deterministic workflow step. Making it a workflow activity (not a standalone service) means:

- It participates in the saga's compensation flow naturally
- If the LLM call fails, the workflow handles it like any other activity failure
- No additional service invocation hop — the Dapr sidecar on the workflow-service pod makes the Conversation API call directly
- The workflow remains deterministic — the step order is fixed, only the fraud assessment is AI-powered
