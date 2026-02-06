# AI Integration Architecture

## Overview

This phase introduces AI into the Dapr microservices demo in two ways:

1. **Phase 7 (Manual):** "Copy for AI" button exports pending orders for fraud review in Claude Desktop
2. **Phase 7-A (Fraud Check):** AI-powered fraud scoring in the order fulfillment workflow, using the Dapr Conversation API to call Claude

The key teaching point: an LLM call fits into a deterministic Dapr Workflow as a regular activity. The workflow stays deterministic (fixed step order), but one step uses AI for risk assessment. The LLM returns a score (0-100), and the workflow applies a threshold — this is more honest about what LLMs can do than a binary yes/no.

## Updated Order Fulfillment Workflow (Phase 7-A)

```
Before (Phase 5 — 4 steps):           After (Phase 7-A — 6 steps):

1. Validate Order                      1. Validate Order
2. Reserve Inventory                   2. Reserve Inventory
3. Process Payment                     3. Check Fraud (NEW — scores 0-100 via Claude)
4. Notify Customer                        ↳ if score >= 80: compensate, reject
                                       4. Process Payment
                                       5. Notify Customer
                                       6. Record Order (NEW — saves to state store)
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
  │    │  Fetch order history from order-service (via sidecar)
  │    │  Build prompt with order details + history
  │    │  (customer, product, category, quantity, total, address, timestamps)
  │    │
  │    │  POST http://localhost:3500/v1.0-alpha1/conversation/anthropic-llm/converse
  │    │  { "inputs": [{ "content": prompt }] }
  │    │        │
  │    │        ▼
  │    │  Dapr sidecar → conversation.anthropic → Claude API
  │    │        │
  │    │        ▼
  │    │  Parse response: { score: 0-100, reasoning: "..." }
  │    │
  │    ├─ score < 80  → continue to payment
  │    └─ score >= 80 → ReleaseInventoryActivity (compensation) → reject order
  │
  ├─ Step 4: ProcessPaymentActivity
  ├─ Step 5: NotifyCustomerActivity
  └─ Step 6: RecordOrderActivity (NEW)
       │
       │  Calls order-service POST /orders/record
       │  Saves order with status "pending_shipment" + fraud score
       │  (fire-and-forget — don't fail workflow if recording fails)
```

### Activities vs Service Calls

The workflow orchestrates **activities** (in-process C# classes), not service calls directly. Each activity then makes outbound calls via the Dapr sidecar as needed:

| Activity | External Call | Via |
|----------|--------------|-----|
| ValidateOrderActivity | None | Pure in-process logic |
| ReserveInventoryActivity | catalog-service | `DaprClient.InvokeMethodAsync()` |
| CheckFraudActivity | Claude API + order-service | `HttpClient` → Dapr Conversation API (sidecar) + order history via sidecar |
| ProcessPaymentActivity | None | Simulated payment (in-process) |
| NotifyCustomerActivity | notification-service | `DaprClient.PublishEventAsync()` (pub/sub) |
| RecordOrderActivity | order-service | `DaprClient.InvokeMethodAsync()` |

This separation is required because the workflow engine replays/checkpoints execution for durability. Side effects (HTTP calls, LLM calls, pub/sub) must be isolated inside activities — the workflow itself stays deterministic.

### Graceful Degradation

If the Conversation API is unavailable (no API key, service error, timeout), the fraud check **returns score 0** with `riskLevel: "unknown"`. This means:

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

### Load Balancing Note (minikube vs AKS)

This phase runs on minikube for local development. The load balancing pattern is the same as Phase 6 (AKS) but without Azure Load Balancer:

| Environment | L4 (Packet Routing) | L7 (HTTP Routing) |
|-------------|---------------------|-------------------|
| **minikube** | `minikube tunnel` or port-forward | nginx-ingress |
| **AKS (Phase 6)** | Azure Load Balancer | nginx-ingress |

In minikube, traffic enters via `minikube tunnel` (which exposes LoadBalancer services to localhost) or `kubectl port-forward`. nginx-ingress then provides the same L7 routing as on AKS — reading HTTP paths and routing to backend pods.

See Phase 6's ARCHITECTURE.md for detailed explanation of L4/L7 load balancing layers.

## What Changed from Phase 5

### Workflow-Service Changes

| File | Change |
|------|--------|
| `Activities/CheckFraudActivity.cs` | New — fetches order history, calls Dapr Conversation API, returns score 0-100 |
| `Activities/RecordOrderActivity.cs` | New — saves order to order-service state store |
| `Models/OrderModels.cs` | Added `FraudCheckResult` (score-based), `RecordOrderRequest` |
| `Workflows/OrderFulfillmentWorkflow.cs` | 6-step saga: fraud check (step 3) + record order (step 6) |
| `Program.cs` | Registered new activities, added `IHttpClientFactory` |

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
  "outputs": [{ "result": "{\"score\": 15, \"reasoning\": \"...\"}" }]
}
```

The .NET Dapr SDK doesn't have a native Conversation API client yet, so CheckFraudActivity uses `IHttpClientFactory` to make the HTTP call directly.

### Dapr Components

One new component (in `03-components/`):

| Component | Type | Purpose |
|-----------|------|---------|
| `anthropic-llm` | `conversation.anthropic` | LLM calls via Dapr Conversation API |

Scoped to `workflow-service`.

### Order-Service Changes

New endpoints for the order lifecycle:

```
POST /orders/record (called by RecordOrderActivity)
  └─ Save order to state store with status, fraud score, transaction ID
  └─ Append orderId to order index

POST /orders/{id}/ship
  └─ Set status to "shipped", add shippedAt timestamp

POST /orders/{id}/cancel
  └─ Set status to "cancelled", add cancelledAt timestamp
  └─ Restore inventory via catalog-service (GET product, PUT with restored stock)

GET /orders (list all)
  └─ Read order index from state store
  └─ Read each order by ID
  └─ Return array
```

### Frontend Changes

- **Orders panel** — Table below products showing all orders with status badges and fraud scores
- **Ship/Cancel buttons** — For pending_shipment orders; cancel restores inventory
- **"Copy for AI" button** — Exports pending orders as a fraud review prompt
- **6-step saga display** — Validate → Reserve → Check Fraud → Payment → Notify → Record Order
- **Fraud score display** — Color-coded score (green/yellow/orange/red) with reasoning on hover
- **Success message** — "Order Pending Shipment" instead of "Order Completed"

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
