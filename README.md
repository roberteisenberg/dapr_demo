# Dapr Microservices Demo

A hands-on project demonstrating Dapr microservices from local development to Kubernetes deployment.

## What You'll Learn

- **Dapr Building Blocks**: State Management, Pub/Sub, Service Invocation
- **Polyglot Services**: Go, Python, Node.js working together
- **Deployment Progression**: Local → Docker → Kubernetes
- **Infrastructure Portability**: Switch from Redis to RabbitMQ without code changes

## Quick Start

Start with local development - no containers needed for your code:

```bash
cd deployments/local
dapr init                    # One-time setup (starts Redis)
./scripts/setup-local.sh     # Install dependencies
dapr run -f .                # Start all services
```

Then test:
```bash
./scripts/test-local.sh
```

See [deployments/local/README.md](deployments/local/README.md) for detailed instructions.

## Services

| Service | Language | Purpose |
|---------|----------|---------|
| catalog-service | Go | Product catalog CRUD, state management |
| order-service | Python | Order processing, service invocation, pub/sub |
| notification-service | Node.js | Event subscriber |

## Project Roadmap

| Phase | Description | Status |
|-------|-------------|--------|
| 1, 1-A | [Local](deployments/local/) + Redis→RabbitMQ switch | Available |
| 2, 2-A | Docker Compose + Redis→RabbitMQ switch | Planned |
| 3, 3-A | Kubernetes + Redis→RabbitMQ switch | Planned |
| 4 | Observability (Zipkin) | Planned |
| 5 | Workflow (.NET Dapr Workflow) | Planned |
| 6+ | Cloud, Secrets, CI/CD, API Management | Planned |

See [ROADMAP.md](ROADMAP.md) for details.

## Key Demonstration: Infrastructure Portability

One of Dapr's main features is swapping infrastructure without code changes. Each deployment type demonstrates switching pub/sub from Redis to RabbitMQ:

```bash
# Local example - switch from Redis to RabbitMQ
cp components/templates/pubsub-rabbitmq.yaml components/pubsub.yaml
dapr run -f .   # Same code, different infrastructure
```

## Resources

- [Dapr Documentation](https://docs.dapr.io/)
- [Dapr Building Blocks](https://docs.dapr.io/concepts/building-blocks-concept/)
