# Kubernetes Architecture with Dapr Workflow

## Overview

Four polyglot microservices deployed to Kubernetes with Dapr sidecars automatically injected. NGINX Ingress with a Dapr sidecar serves as an API gateway for external access. **Dapr Workflow** provides saga-based order orchestration with automatic compensation on failure. Zipkin provides distributed tracing for visualizing workflow execution.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster (minikube)                         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        dapr-demo namespace                              │ │
│  │                                                                         │ │
│  │    ┌─────────────────┐                           ┌─────────────────┐   │ │
│  │    │  NGINX Ingress  │ ◄── External (:8080)      │     Zipkin      │   │ │
│  │    │  + Dapr sidecar │                           │   (:9411)       │   │ │
│  │    │  (api-gateway)  │──────────────────────────►│ Trace Collector │   │ │
│  │    └────────┬────────┘                           └─────────────────┘   │ │
│  │             │ /v1.0/invoke/{app-id}/method/{endpoint}      ▲           │ │
│  │             ▼                                              │           │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐    │ │
│  │  │ catalog-service  │  │ workflow-service │  │notification-service│   │ │
│  │  │    (Go)          │◄─│    (.NET 8.0)    │─►│    (Node.js)      │    │ │
│  │  │    + daprd       │  │    + daprd       │  │    + daprd        │    │ │
│  │  └────────┬─────────┘  └────────┬─────────┘  └─────────┬─────────┘    │ │
│  │           │                     │                      │              │ │
│  │           │      ┌──────────────┴──────────────┐       │              │ │
│  │           │      │    Dapr Workflow Runtime    │       │              │ │
│  │           │      │  (state persisted in Redis) │       │              │ │
│  │           │      └──────────────┬──────────────┘       │              │ │
│  │           │                     │                      │              │ │
│  │           └─────────────────────┼──────────────────────┘              │ │
│  │                                 ▼                                      │ │
│  │                    ┌────────────────────────┐                         │ │
│  │                    │   Redis / MongoDB      │                         │ │
│  │                    │   (state + pub/sub)    │                         │ │
│  │                    └────────────────────────┘                         │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        dapr-system namespace                            │ │
│  │   dapr-operator | dapr-sidecar-injector | dapr-placement | dapr-sentry  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Automatic Sidecar Injection

Unlike Docker Compose where we explicitly defined sidecar containers, Kubernetes uses the Dapr operator to automatically inject sidecars based on pod annotations:

```yaml
metadata:
  annotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: "catalog-service"
    dapr.io/app-port: "8080"
```

The Dapr sidecar injector watches for pods with `dapr.io/enabled: "true"` and automatically adds a `daprd` container to the pod spec.

## API Gateway Pattern

The NGINX Ingress controller runs with a Dapr sidecar, making it a Dapr-aware API gateway:

```yaml
# config/ingress-values.yaml
controller:
  podAnnotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: "api-gateway"
    dapr.io/app-port: "80"
    dapr.io/sidecar-listen-addresses: "0.0.0.0"
```

External requests to `/v1.0/invoke/{app-id}/method/{endpoint}` are routed to the ingress controller's Dapr sidecar, which then uses Dapr service invocation to reach backend services.

**Why this pattern?**
- Single entry point for all services
- Backend services don't need Kubernetes Service objects
- Dapr handles service discovery, retries, and mTLS
- External callers use the standard Dapr invoke API

## Distributed Tracing

Phase 4 adds Zipkin distributed tracing. Every Dapr sidecar automatically sends trace spans to Zipkin, providing end-to-end visibility into request flows.

### Tracing Configuration

A Dapr Configuration resource defines the tracing settings:

```yaml
# manifests/03-components/tracing.yaml
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: tracing
  namespace: dapr-demo
spec:
  tracing:
    samplingRate: "1"    # 100% of requests traced (demo only)
    zipkin:
      endpointAddress: "http://zipkin.dapr-demo.svc.cluster.local:9411/api/v2/spans"
```

Services reference this configuration via annotation:

```yaml
metadata:
  annotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: "catalog-service"
    dapr.io/config: "tracing"    # References the Configuration above
```

### How Traces Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────►│ api-gateway │────►│order-service│────►│catalog-svc  │
│ (curl/app)  │     │   daprd     │     │   daprd     │     │   daprd     │
└─────────────┘     └──────┬──────┘     └──────┬──────┘     └──────┬──────┘
                           │                   │                   │
                           │  trace spans      │  trace spans      │  trace spans
                           ▼                   ▼                   ▼
                    ┌─────────────────────────────────────────────────────┐
                    │                      Zipkin                         │
                    │  Collects spans, builds trace tree, provides UI     │
                    └─────────────────────────────────────────────────────┘
```

### What Gets Traced

| Operation Type | Example | Traced? |
|----------------|---------|---------|
| Service invocation | order-service → catalog-service | Yes |
| Pub/sub publish | order-service publishes OrderCreated | Yes |
| Pub/sub subscribe | notification-service receives event | Yes |
| State operations | Save/get order state | Yes |
| External HTTP | Any outgoing request via sidecar | Yes |

### Viewing Traces in Zipkin

1. Open http://localhost:9411 (after port-forward)
2. Click **"Run Query"** to see recent traces
3. Click a trace to see the full span tree
4. Each span shows:
   - Service name and operation
   - Duration (for latency analysis)
   - Tags (HTTP method, status code, etc.)
   - Errors (if any)

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Trace** | A complete request flow across multiple services |
| **Span** | A single operation within a trace (one service call) |
| **Trace ID** | Unique identifier propagated across all spans in a trace |
| **Parent-child** | Spans form a tree showing call hierarchy |
| **Sampling rate** | What percentage of requests to trace (1 = 100%) |

**Why 100% sampling?** For demo purposes. Production typically uses 1-10% to reduce overhead.

## Dapr Workflow

Phase 5 adds a .NET workflow service using the Dapr Workflow SDK. The workflow implements the **saga pattern** for distributed transactions with automatic compensation on failure.

### What is the Saga Pattern?

A saga is a sequence of local transactions where each step has a corresponding **compensation** action. If any step fails, the saga executes compensations for all completed steps in reverse order.

```
Success Path:
  Step 1 → Step 2 → Step 3 → Step 4 → COMPLETE

Failure at Step 3:
  Step 1 → Step 2 → Step 3 (FAIL) → Compensate Step 2 → FAILED
```

### Order Fulfillment Workflow

The `OrderFulfillmentWorkflow` orchestrates a 4-step saga:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        OrderFulfillmentWorkflow                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐                                                    │
│  │ 1. ValidateOrder    │ Check orderId, productId, quantity, email          │
│  │    Activity         │ Compensation: None (no state changed)              │
│  └──────────┬──────────┘                                                    │
│             │ valid                                                         │
│             ▼                                                               │
│  ┌─────────────────────┐                                                    │
│  │ 2. ReserveInventory │ GET catalog-service/products/{id}                  │
│  │    Activity         │ PUT with decremented stock                         │
│  │                     │ Compensation: ReleaseInventoryActivity             │
│  └──────────┬──────────┘                                                    │
│             │ reserved                                                      │
│             ▼                                                               │
│  ┌─────────────────────┐                                                    │
│  │ 3. ProcessPayment   │ Simulate payment (fails if amount > $10k)          │
│  │    Activity         │ On failure: triggers ReleaseInventoryActivity      │
│  └──────────┬──────────┘                                                    │
│             │ paid                                                          │
│             ▼                                                               │
│  ┌─────────────────────┐                                                    │
│  │ 4. NotifyCustomer   │ Publish to pub/sub "orders" topic                  │
│  │    Activity         │ Compensation: None (fire-and-forget)               │
│  └──────────┬──────────┘                                                    │
│             │                                                               │
│             ▼                                                               │
│        COMPLETED                                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Compensation Flow

When payment fails, the workflow automatically compensates:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Validate   │────►│   Reserve   │────►│   Payment   │────►│   FAILED    │
│   (pass)    │     │   (pass)    │     │   (FAIL)    │     │             │
└─────────────┘     └──────┬──────┘     └──────┬──────┘     └─────────────┘
                           │                   │
                           │ ◄─────────────────┘
                           │   Compensation triggered
                           ▼
                    ┌─────────────┐
                    │   Release   │  Restore stock to original value
                    │  Inventory  │
                    └─────────────┘
```

### Workflow State Management

Dapr Workflow uses the configured state store (Redis) to persist:
- Workflow instance state
- Activity results
- Compensation history

This enables:
- **Durability**: Workflows survive pod restarts
- **Idempotency**: Same instance ID prevents duplicate processing
- **Observability**: Full execution history available

### Workflow Configuration

The workflow service uses Dapr annotations like other services:

```yaml
annotations:
  dapr.io/enabled: "true"
  dapr.io/app-id: "workflow-service"
  dapr.io/app-port: "8083"
  dapr.io/config: "tracing"
```

The state store component must have `actorStateStore: "true"` for workflow state:

```yaml
# Already configured in statestore.yaml
metadata:
- name: actorStateStore
  value: "true"
```

### Workflow Traces in Zipkin

Workflow execution generates detailed traces showing:
- Each activity as a separate span
- Service invocations (workflow → catalog-service)
- Pub/sub events (workflow → notification-service)
- Compensation activities when triggered

Search for `workflow-service` in Zipkin to see the full saga execution.

## Service Discovery

In Kubernetes, Dapr uses the Kubernetes DNS for service discovery. The Dapr sidecar on the api-gateway can invoke `catalog-service` because:

1. The Dapr operator registers each Dapr-enabled pod
2. Dapr uses Kubernetes headless services for sidecar-to-sidecar communication
3. mTLS is automatically enabled via Sentry (the Dapr CA)

## What's Different from Docker Compose

| Aspect | Docker Compose | Kubernetes + Workflow |
|--------|----------------|------------------------|
| Sidecar lifecycle | Explicit containers, manual wiring | Auto-injected by operator |
| Service discovery | Placement service only | Dapr + Kubernetes DNS |
| mTLS | Not enabled | Automatic via Sentry |
| Scaling | Single replica | `kubectl scale deployment/catalog-service --replicas=3` |
| Health checks | Container health | K8s probes + Dapr health |
| Dashboard | Doesn't work (no control plane) | `dapr dashboard -k` |
| **Tracing** | **Not available** | **Zipkin at :9411** |
| **Workflow** | **Not available** | **Dapr Workflow with saga pattern** |
| Config | docker-compose.yml | K8s manifests + Dapr Configuration CRD |

## Dapr Control Plane

`dapr init -k` installs the Dapr control plane in the `dapr-system` namespace:

| Component | Purpose |
|-----------|---------|
| dapr-operator | Manages Dapr components and sidecars |
| dapr-sidecar-injector | Injects daprd containers into pods |
| dapr-placement | Actor placement (same as Docker) |
| dapr-sentry | Certificate authority for mTLS |
| dapr-dashboard | Web UI for Dapr |

## Infrastructure Portability

Same pattern as local and Docker - swap component YAML without code changes:

**Phase 3-A: Pub/Sub Redis → RabbitMQ**
```bash
./scripts/deploy-all.sh --pubsub rabbitmq
```

**Phase 3-B: State Store Redis → MongoDB**
```bash
./scripts/deploy-all.sh --statestore mongodb
```

The deploy script copies the appropriate template to the active component file and applies it to Kubernetes.

## Testing Flow

```
                    ┌───────────────────────────────┐
                    │    curl localhost:8080        │
                    │  /v1.0/invoke/catalog-service │
                    │       /method/products        │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │      NGINX Ingress            │
                    │   routes /v1.0/* to daprd     │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │   api-gateway Dapr sidecar    │
                    │  invokes catalog-service      │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │   catalog-service daprd       │
                    │  forwards to app :8080        │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │     catalog-service app       │
                    │    returns product data       │
                    └───────────────────────────────┘
```

## What You'll Learn

- **Automatic sidecar injection** - No explicit sidecar containers needed
- **Dapr control plane** - Operator, sentry, dashboard working together
- **API gateway pattern** - NGINX Ingress + Dapr sidecar for external access
- **Kubernetes-native Dapr** - Components as K8s CRDs, standard manifests
- **mTLS** - Automatic encryption between sidecars via Sentry
- **Dapr dashboard** - Full visibility into services, components, configurations
- **Distributed tracing** - Zipkin integration via Dapr Configuration
- **Trace visualization** - End-to-end request flow analysis
- **Debugging distributed systems** - Using traces to identify latency and errors
- **Dapr Workflow SDK** - Building durable workflows in .NET
- **Saga pattern** - Multi-step distributed transactions with compensation
- **Workflow orchestration** - Coordinating multiple services in a transaction
- **Automatic compensation** - Rollback on failure without manual intervention
