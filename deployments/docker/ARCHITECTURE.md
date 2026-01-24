# Docker Compose Architecture

## Overview

Three polyglot microservices running as containers, each paired with a Dapr sidecar container. Demonstrates the same Dapr building blocks as the local deployment, but in a containerized environment with explicit sidecar management.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Docker Network (dapr-network)                        │
│                                                                          │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐  │
│  │  catalog-service    │  │   order-service     │  │ notification-   │  │
│  │  (Go) :8080         │  │   (Python) :8081    │  │ service         │  │
│  │                     │  │                     │  │ (Node.js) :8082 │  │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │  │  ┌────────────┐ │  │
│  │  │ catalog-dapr  │  │  │  │  order-dapr   │  │  │  │notif-dapr  │ │  │
│  │  │ daprd :3500   │  │  │  │ daprd :3500   │  │  │  │daprd :3500 │ │  │
│  │  └───────┬───────┘  │  │  └───────┬───────┘  │  │  └─────┬──────┘ │  │
│  └──────────┼───────────┘  └──────────┼──────────┘  └────────┼────────┘  │
│             │                         │                      │           │
│             └────────────┬────────────┴──────────────────────┘           │
│                          │                                               │
│              ┌───────────▼────────────┐     ┌──────────────────┐         │
│              │        Redis           │     │  Dapr Placement  │         │
│              │  (State + Pub/Sub)     │     │     :50006       │         │
│              │       :6379            │     └──────────────────┘         │
│              └────────────────────────┘                                  │
└──────────────────────────────────────────────────────────────────────────┘
```

## The Sidecar Pattern in Docker

In local development, `dapr run` manages sidecars automatically. In Docker, we manage them explicitly:

```yaml
# The application container
catalog-service:
  build: ../../services/catalog-service
  ports:
    - "8080:8080"
  networks:
    - dapr-network

# The Dapr sidecar container (shares network with the app)
catalog-dapr:
  image: "daprio/daprd:1.14.4"
  command: ["./daprd", "--app-id", "catalog-service", "--app-port", "8080", ...]
  network_mode: "service:catalog-service"
```

**Key concept: `network_mode: "service:catalog-service"`**

This makes the sidecar share the app's network namespace. The sidecar and app communicate over `localhost`, just like in local development. From the app's perspective, the Dapr sidecar is always at `localhost:3500` (HTTP) or `localhost:50001` (gRPC).

## What's Different from Local

| Aspect | Local (Phase 1) | Docker (Phase 2) |
|--------|----------------|------------------|
| Runtime | `dapr run` from source | Containers with daprd sidecars |
| Sidecar lifecycle | Managed by Dapr CLI | Separate container, starts independently |
| Networking | All on localhost | Docker bridge network |
| Service discovery | Dapr mDNS | Placement service |
| Component hosts | `localhost:6379` | `redis:6379` (container name) |
| Startup ordering | Sequential | Async (needs retry logic) |

## Order Flow

The same flow as local, but across containers:

1. **order-service** calls **catalog-service** via Dapr **service invocation**
   - order-dapr resolves `catalog-service` via the placement service
   - Request routes through the Docker network to catalog-dapr
2. **order-service** saves the order to Redis via Dapr **state management**
   - order-dapr connects to `redis:6379` (Docker DNS resolves the container name)
3. **order-service** publishes an "order-created" event via Dapr **pub/sub**
   - order-dapr publishes to Redis pub/sub
4. **notification-service** receives the event
   - notification-dapr delivers it to the app's `/orders` endpoint

## Startup and Retry Logic

In Docker, the app container and sidecar container start independently. The sidecar needs to:
1. Connect to the placement service
2. Load component configurations
3. Start the gRPC/HTTP API

The app may start before the sidecar is ready. The catalog-service handles this with retry logic:

```go
// Wait for Dapr sidecar to be ready
for i := 0; i < maxRetries; i++ {
    client, err = dapr.NewClient()
    if err == nil {
        break
    }
    log.Printf("Waiting for Dapr sidecar... (attempt %d/%d)", i+1, maxRetries)
    time.Sleep(2 * time.Second)
}
```

The Python Dapr SDK (order-service) handles retries internally via gRPC reconnection. The Node.js notification-service uses HTTP-based subscription (Dapr calls the app, not the other way around), so no client initialization is needed.

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
    value: redis:6379      # Docker container name, not localhost
  - name: redisPassword
    value: ""
```

### Pub/Sub (components/pubsub.yaml)

Redis (default):
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
    value: redis:6379      # Docker container name, not localhost
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
    value: "amqp://rabbitmq:5672"   # Docker container name
```

## Docker Compose Structure

The docker-compose.yml defines 8 containers:

| Container | Image | Role |
|-----------|-------|------|
| redis | redis:7-alpine | State store + Pub/sub backend |
| placement | daprio/dapr:1.14.4 | Dapr actor placement |
| catalog-service | Built from services/catalog-service | Go application |
| catalog-dapr | daprio/daprd:1.14.4 | Catalog sidecar |
| order-service | Built from services/order-service | Python application |
| order-dapr | daprio/daprd:1.14.4 | Order sidecar |
| notification-service | Built from services/notification-service | Node.js application |
| notification-dapr | daprio/daprd:1.14.4 | Notification sidecar |

## Dapr Dashboard and Tooling

The Dapr dashboard (`dapr dashboard`) does **not** work with Docker Compose deployments. This is a known gap in the Dapr developer experience:

| Deployment | Dashboard Support | How It Discovers Sidecars |
|------------|-------------------|---------------------------|
| Local | Works | CLI tracks instances in `~/.dapr` |
| Docker Compose | Not supported | No discovery mechanism available |
| Kubernetes | Works | Control plane (operator) via K8s API |

Docker Compose is "manual sidecar management" - you get containerization but lose the CLI tooling (`dapr list`, `dapr dashboard`, etc.) that relies on either local runtime state or a Kubernetes control plane.

**Debugging in Docker Compose** relies on container logs instead:

```bash
docker-compose logs catalog-service      # App logs
docker-compose logs catalog-dapr         # Sidecar logs
docker-compose logs placement            # Placement service logs
docker-compose ps                        # Container status
```

This is an intentional tradeoff for the demo: Docker Compose teaches how sidecars actually work before Kubernetes abstracts it away again with automatic injection and the full control plane.

## What You'll Learn

- **Sidecar pattern** - Explicit sidecar container management with `network_mode`
- **Container networking** - Service discovery via Docker DNS and Dapr placement
- **Startup ordering** - Handling async sidecar initialization with retries
- **Dapr in containers** - Same building blocks, different runtime environment
- **Infrastructure portability** - Swap Redis for RabbitMQ by changing a YAML file
