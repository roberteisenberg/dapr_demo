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
| 2, 2-A | [Docker](deployments/docker/) + Redis→RabbitMQ switch | Available |
| 3, 3-A, 3-B | [Kubernetes](deployments/kubernetes/) + Pub/Sub swap + State store swap | Available |
| 4 | Observability (Zipkin) | Planned |
| 5 | Workflow (.NET Dapr Workflow) | Planned |
| 6+ | Cloud, Secrets, CI/CD, API Management | Planned |

See [ROADMAP.md](ROADMAP.md) for details.

## Deployment Progression

Each phase builds on the previous, adding deployment complexity while keeping service code unchanged:

1. **Local** - Run from source with `dapr run`. Learn Dapr basics.
2. **Docker** - Containers with explicit Dapr sidecar management. Learn the sidecar pattern.
3. **Kubernetes** - Auto-injected sidecars, Ingress API gateway, React frontend. Production patterns.

The same `services/` directory (with Dockerfiles) is shared between Docker and Kubernetes deployments. Local embeds its own service copies (no Dockerfiles needed).

## Key Demonstration: Infrastructure Portability

Dapr's component abstraction lets you swap infrastructure without code changes. The demo progressively demonstrates this:

- **Phases 1-A, 2-A, 3-A**: Switch pub/sub from Redis to RabbitMQ
- **Phase 3-B**: Switch state store from Redis to MongoDB

```bash
# Example - swap pub/sub backend (same pattern in every deployment)
cp components/templates/pubsub-rabbitmq.yaml components/pubsub.yaml
# Restart services - same code, different infrastructure
```

## Resources

- [Dapr Documentation](https://docs.dapr.io/)
- [Dapr Building Blocks](https://docs.dapr.io/concepts/building-blocks-concept/)
