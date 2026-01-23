# Local Deployment Architecture

## Overview

Three polyglot microservices communicating through Dapr sidecars, demonstrating state management, service invocation, and pub/sub messaging.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        YOUR LAPTOP                                   │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ catalog-service  │  │  order-service   │  │notification-service│ │
│  │ (Go) :8080       │  │ (Python) :8081   │  │ (Node.js) :8082   │  │
│  └────────┬─────────┘  └────────┬─────────┘  └─────────┬─────────┘  │
│           │                     │                      │            │
│  ┌────────▼─────────┐  ┌────────▼─────────┐  ┌─────────▼─────────┐  │
│  │  Dapr Sidecar    │  │  Dapr Sidecar    │  │  Dapr Sidecar     │  │
│  │  :3500           │  │  :3501           │  │  :3502            │  │
│  └────────┬─────────┘  └────────┬─────────┘  └─────────┬─────────┘  │
│           │                     │                      │            │
│           └─────────────────────┼──────────────────────┘            │
│                                 ▼                                    │
│              ┌──────────────────────────────────┐                   │
│              │   Redis (State) + Pub/Sub        │                   │
│              │   (Redis or RabbitMQ)            │                   │
│              └──────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Order Flow

When you place an order, all three Dapr building blocks are demonstrated:

1. **order-service** calls **catalog-service** via Dapr **service invocation** to check stock
2. **order-service** saves the order to Redis via Dapr **state management**
3. **order-service** publishes an "order-created" event via Dapr **pub/sub**
4. **notification-service** receives the event and logs it

## Project Structure

```
deployments/local/
├── catalog-service/          # Go - Product CRUD, state management
│   ├── main.go
│   ├── go.mod
│   └── go.sum
├── order-service/            # Python - Orders, service invocation, pub/sub
│   ├── app.py
│   └── requirements.txt
├── notification-service/     # Node.js - Event subscriber
│   ├── index.js
│   └── package.json
├── components/               # Dapr component configs
│   ├── statestore.yaml       # Redis state store
│   ├── pubsub.yaml           # Redis or RabbitMQ pub/sub
│   └── templates/            # Alternative configs (Redis/RabbitMQ)
├── scripts/                  # Helper scripts
│   ├── test-local.sh         # Full integration test
│   └── ...
└── dapr.yaml                 # Multi-app run config
```

## Dapr Building Blocks

### 1. State Management (catalog-service)

Products are stored in Redis via Dapr state API:

```go
// Save product
daprClient.SaveState(ctx, "statestore", productID, productJSON, nil)

// Get product
item, err := daprClient.GetState(ctx, "statestore", productID, nil)
```

### 2. Service Invocation (order-service → catalog-service)

Order service calls catalog service through Dapr (not direct HTTP):

```python
# Call catalog-service via Dapr
result = dapr_client.invoke_method(
    app_id='catalog-service',
    method_name=f'products/{product_id}',
    http_verb='GET'
)
```

**Why use Dapr invocation?**
- Service discovery (no hardcoded URLs)
- Built-in retries
- Distributed tracing
- mTLS encryption (in production)

### 3. Pub/Sub Messaging (order-service → notification-service)

Order service publishes events:
```python
dapr_client.publish_event(
    pubsub_name='pubsub',
    topic_name='orders',
    data=order_data
)
```

Notification service subscribes:
```javascript
// Subscribe to 'orders' topic
app.post('/orders', (req, res) => {
    console.log('Order received:', req.body);
    res.sendStatus(200);
});
```

## Component Configuration

### State Store (components/statestore.yaml)

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.redis
  version: v1
  metadata:
  - name: redisHost
    value: localhost:6379
```

### Pub/Sub (components/pubsub.yaml)

Redis (default from `dapr init`):
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
spec:
  type: pubsub.redis
  version: v1
  metadata:
  - name: redisHost
    value: localhost:6379
```

RabbitMQ (alternative - see templates/):
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
spec:
  type: pubsub.rabbitmq
  version: v1
  metadata:
  - name: host
    value: "amqp://localhost:5672"
```

## What You'll Learn

- **Dapr State Management** - CRUD operations via state API
- **Dapr Service Invocation** - Service-to-service calls without hardcoded URLs
- **Dapr Pub/Sub** - Event-driven messaging with pluggable backends
- **Dapr Components** - Swap Redis for RabbitMQ without code changes
- **Polyglot Services** - Go, Python, Node.js working together
- **Sidecar Pattern** - Each app has its own Dapr sidecar
