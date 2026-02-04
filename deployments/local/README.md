# Local Development with Dapr

> **Note**: These instructions use bash (Linux/macOS/WSL2). Run them from a Linux terminal.

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed explanations of how the services and Dapr building blocks work.

## Why Embedded Services?

This deployment includes the service source code directly in this directory. Unlike Docker and Kubernetes deployments (which build container images from a shared `services/` directory), Local development runs services directly from source using `dapr run`. No Dockerfiles needed - just your code and the Dapr CLI.

## Prerequisites
**Note**
Docker: You must have Docker Desktop for Windows installed and configured to use the WSL2 backend so that Dapr can start its sidecars (Redis/Zipkin) correctly.

Open a WSL2 or Linux terminal

1. **Install Dapr CLI and initialize:**
   ```bash
   wget -q https://raw.githubusercontent.com/dapr/cli/master/install/install.sh -O - | /bin/bash
   dapr init
   ```
   This starts Redis and Zipkin containers automatically.

2. **Install language runtimes:**
   Runtimes: You must install Go, Python, and Node.js inside your WSL2 distribution (e.g., Ubuntu), not just on Windows. 
   - [Go 1.21+](https://go.dev/doc/install)
   - [Python 3.9+](https://www.python.org/downloads/)
   - [Node.js 18+](https://nodejs.org/)

## Quick Start

### 1. Install dependencies

```bash
cd deployments/local
cd catalog-service && go mod download && cd ..
cd order-service && pip3 install -r requirements.txt && cd ..
cd notification-service && npm install && cd ..
```

### 2. Start all services

```bash
dapr run -f .
```

This uses the `dapr.yaml` multi-app configuration to start all services at once.

**Alternative: Run services manually** (useful for learning/debugging):
```bash
# Terminal 1
cd catalog-service && dapr run --app-id catalog-service --app-port 8080 --resources-path ../components -- go run main.go

# Terminal 2
cd order-service && dapr run --app-id order-service --app-port 8081 --resources-path ../components -- python3 app.py

# Terminal 3
cd notification-service && dapr run --app-id notification-service --app-port 8082 --resources-path ../components -- node index.js
```

Expected output:
```
== APP - catalog-service == Dapr client initialized successfully
== APP - catalog-service == Catalog Service listening on port 8080
== APP - order-service == Order Service starting on port 8081
== APP - notification-service == Notification Service listening on port 8082
```

### 3. Test the full flow

In a new terminal:

```bash
# Create a product
curl -X POST http://localhost:8080/products \
  -H "Content-Type: application/json" \
  -d '{"id": "laptop-001", "name": "Gaming Laptop", "price": 999.99, "stock": 10}'

# Place an order (triggers service invocation + pub/sub)
curl -X POST http://localhost:8081/orders \
  -H "Content-Type: application/json" \
  -d '{"orderId": "order-001", "productId": "laptop-001", "quantity": 2}'
```

Watch the `dapr run` terminal - you'll see the order flow across all three services.

Or run the test script:
```bash
./scripts/test-local.sh
```

### 4. Stop the services

Press `Ctrl+C` or run:
```bash
dapr stop -f .
```

## Switching Pub/Sub Backend

By default, pub/sub uses **Redis** (started automatically by `dapr init`).

One key feature of Dapr is the ability to switch infrastructure components without changing code. To demonstrate this, you can switch to RabbitMQ:

1. Start RabbitMQ:
   ```bash
   docker run -d --name rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management
   ```

2. Switch the component:
   ```bash
   cp components/templates/pubsub-rabbitmq.yaml components/pubsub.yaml
   ```

3. Restart services:
   ```bash
   dapr stop -f . && dapr run -f .
   ```

4. Test again - same code, different infrastructure.

To switch back to Redis:
```bash
cp components/templates/pubsub-redis.yaml components/pubsub.yaml
```

## Troubleshooting

**"Connection refused" errors**
- Check Redis is running: `docker ps | grep dapr_redis`
- If not running: `dapr init` (or `dapr uninstall && dapr init` for clean start)

**"App not found" errors**
- Check all services are running: `dapr list`

**View Dapr dashboard**
```bash
dapr dashboard
```
Opens http://localhost:8080 with service status, components, and configurations.

## Project Structure

```
deployments/local/
├── catalog-service/      # Go - Product CRUD, state management
├── order-service/        # Python - Orders, service invocation, pub/sub
├── notification-service/ # Node.js - Event subscriber
├── components/           # Dapr component configs
│   ├── statestore.yaml   # Redis state store
│   ├── pubsub.yaml       # Redis pub/sub (default)
│   └── templates/        # Alternative configs
│       ├── pubsub-redis.yaml
│       └── pubsub-rabbitmq.yaml
├── scripts/              # Helper scripts
└── dapr.yaml             # Multi-app run configuration
```
