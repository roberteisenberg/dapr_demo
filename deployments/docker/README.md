# Docker Compose Deployment

Run the Dapr microservices demo in containers with Docker Compose.

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed explanations of the sidecar pattern, Docker networking, and how this differs from local development.

## Why Shared Services?

This deployment builds container images from the shared `services/` directory at the project root. Unlike the local deployment (which embeds service source directly), Docker and Kubernetes deployments share the same service code and Dockerfiles. The deployment-specific configuration (docker-compose.yml, Dapr components) lives here.

## Prerequisites

- Docker and Docker Compose installed

No local language runtimes (Go, Python, Node.js) are needed - everything builds inside containers.

### Coming from Local Deployment (Phase 1)?

The Docker deployment is fully self-contained - it runs its own Redis and Dapr sidecars. It cannot share the infrastructure from `dapr init` (different Docker network). Clean up the local deployment first:

```bash
# Stop local Dapr services
cd deployments/local
dapr stop -f .

# Remove Dapr local infrastructure (Redis, Zipkin, placement containers)
dapr uninstall --all
```

Both deployments use ports 6379 (Redis), 8080-8082 (services). They cannot run simultaneously.

To return to the local deployment later, re-initialize: `dapr init`

## Quick Start

### 1. Start all services

```bash
cd deployments/docker
docker-compose up --build
```

Expected output (after builds complete):
```
catalog-service   | Dapr client initialized successfully
catalog-service   | Catalog Service listening on port 8080
order-service     | Order Service starting on port 8081
notification-service | Notification Service listening on port 8082
```

### 2. Test the full flow

In a new terminal, run the test script:
```bash
./scripts/test-services.sh
```

This exercises all 3 Dapr building blocks:
1. **State Management** - Creates a product in catalog-service (saved to Redis via sidecar)
2. **Service Invocation** - order-service calls catalog-service through Dapr (not direct HTTP)
3. **Pub/Sub** - order-service publishes an event, notification-service receives it

Or test manually:

```bash
# 1. Create a product (Dapr State Management)
curl -X POST http://localhost:8080/products \
  -H "Content-Type: application/json" \
  -d '{"id": "laptop-001", "name": "Gaming Laptop", "price": 1299.99, "stock": 10}'

# 2. Place an order (triggers Service Invocation + Pub/Sub)
curl -X POST http://localhost:8081/orders \
  -H "Content-Type: application/json" \
  -d '{"orderId": "order-001", "productId": "laptop-001", "quantity": 2}'

# 3. Verify the notification was received
docker-compose logs notification-service
```

Watch the `docker-compose` terminal - you'll see the order flow across all three services.

### 3. Stop the services

```bash
docker-compose down
```

To also remove volumes (clears Redis data):
```bash
docker-compose down -v
```

## Switching Pub/Sub Backend

By default, pub/sub uses **Redis** (same container as state store).

To switch to RabbitMQ without changing any service code:

1. Stop services:
   ```bash
   docker-compose down
   ```

2. Swap the component:
   ```bash
   cp components/templates/pubsub-rabbitmq.yaml components/pubsub.yaml
   ```

3. Add RabbitMQ to docker-compose.yml (under services):
   ```yaml
   rabbitmq:
     image: rabbitmq:3-management
     container_name: rabbitmq
     ports:
       - "5672:5672"
       - "15672:15672"
     networks:
       - dapr-network
     healthcheck:
       test: ["CMD", "rabbitmq-diagnostics", "ping"]
       interval: 10s
       timeout: 5s
       retries: 5
   ```

4. Restart:
   ```bash
   docker-compose up --build
   ```

5. Test again - same code, different infrastructure.

To switch back to Redis:
```bash
cp components/templates/pubsub-redis.yaml components/pubsub.yaml
```

## Troubleshooting

**"Waiting for Dapr sidecar" messages**
- This is normal. The catalog-service retries Dapr client connection until the sidecar is ready.
- If it fails after 10 attempts, check placement service: `docker-compose logs placement`

**Port conflicts**
- Stop any local Redis or services using the required ports:
  ```bash
  docker-compose down
  lsof -i :6379 -i :8080 -i :8081 -i :8082
  ```

**Rebuild after code changes**
```bash
docker-compose up --build
```

## Project Structure

```
deployments/docker/
├── docker-compose.yml        # All containers (infra + services + sidecars)
├── components/               # Dapr component configs
│   ├── statestore.yaml       # Redis state store
│   ├── pubsub.yaml           # Redis pub/sub (default)
│   └── templates/            # Alternative configs
│       ├── pubsub-redis.yaml
│       └── pubsub-rabbitmq.yaml
├── scripts/                  # Helper scripts
│   └── test-services.sh      # Full integration test
├── README.md
└── ARCHITECTURE.md
```
