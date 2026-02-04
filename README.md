# Dapr Microservices Demo

A hands-on project demonstrating Dapr microservices from local development to cloud-ready Kubernetes — covering Infrastructure as Code, distributed workflows, and AI-powered fraud detection utilizing Dapr workflow to call the Claude API. 

> **Coming Soon:** Dedicated repos and deep dives:
> - AI agent orchestration with Dapr Agents
> - Using Aspire with Dapr
 
> **Note:** This repository is primarily a working reference implementation. It contains separate directories for each phase allowing comparing the implementation code to each topic. The documentation and walkthroughs were added as a companion guide and have not been through formal tutorial-level QA. If you run into gaps or inconsistencies, the code and scripts themselves are the source of truth.

## What You'll Learn

- **Dapr Building Blocks**: State Management, Pub/Sub, Service Invocation, Workflow
- **Polyglot Services**: Go, Python, Node.js, .NET working together
- **Dapr Without Kubernetes**: Local development and Docker Compose with explicit sidecars
- **Dapr With Kubernetes**: Minikube with auto-injected sidecars, scaling to Azure AKS
- **Infrastructure as Code**: Terraform for provisioning Azure AKS clusters
- **API Gateway Patterns**: Simple routing to NGINX Ingress with Dapr sidecar
- **Distributed Tracing**: Zipkin integration for visualizing request flows
- **Saga Pattern**: Dapr Workflow with automatic compensation on failure
- **Infrastructure Portability**: Swap pub/sub (Redis↔RabbitMQ) and state store (Redis↔MongoDB) without code changes
- **AI Integration**: LLM-powered fraud detection via Dapr Conversation API, plus manual AI review workflow
- **Enterprise Security**: TLS (Let's Encrypt), Azure AD login (MSAL.js/PKCE), JWT validation (OAuth2 Proxy), Dapr access control policies
- **CI/CD**: GitHub Actions pipelines (planned)
- **API Management**: Azure APIM gateway (planned)

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
| workflow-service | .NET 8.0 | Order orchestration with saga pattern (Phase 5+) |

## Project Roadmap

| Phase | Description | Status |
|-------|-------------|--------|
| 1, 1-A | [Local](deployments/local/) + Redis→RabbitMQ switch | Available |
| 2, 2-A | [Docker](deployments/docker/) + Redis→RabbitMQ switch | Available |
| 3, 3-A, 3-B | [Kubernetes](deployments/kubernetes/) + React frontend with status panel + infrastructure swaps | Available |
| 4 | [Observability](deployments/kubernetes-phase4-observability/) (Zipkin tracing) | Available |
| 5 | [Workflow](deployments/kubernetes-phase5-workflow/) (.NET Dapr Workflow, saga pattern) | Available |
| 6 | [Cloud (Azure AKS) and Terraform](deployments/kubernetes-phase6-aks/) | Available |
| 7, 7-A | [AI Integration](deployments/kubernetes-phase7-ai/) (Fraud review export, Ship/Cancel orders, AI fraud scoring via Dapr Conversation API) | Available |
| 8 | [Security](deployments/kubernetes-phase8-security/) (Azure AD login, JWT validation, Dapr access control) | Available |
| 9+ | CI/CD, API Management | Planned |

See [ROADMAP.md](ROADMAP.md) for details.

## Deployment Progression

Each phase builds on the previous, adding deployment complexity while keeping service code unchanged:

1. **Local** - Run from source with `dapr run`. Learn Dapr basics.
2. **Docker** - Containers with explicit Dapr sidecar management. Learn the sidecar pattern.
3. **Kubernetes** - Auto-injected sidecars, Ingress API gateway, React frontend with real-time status panel.
4. **Observability** - Zipkin distributed tracing. Visualize request flows across services.
5. **Workflow** - Dapr Workflow with saga pattern. Orchestrate multi-step transactions with compensation.
6. **Cloud (Azure AKS) and Terraform** - AKS cluster with public URL. No port-forward needed.
7. **AI Integration** - Orders panel with Ship/Cancel, "Copy for AI" for fraud review, AI-powered fraud scoring (0-100) in the order workflow via Dapr Conversation API.
8. **Security** - TLS via Let's Encrypt, Azure AD login (MSAL.js with PKCE), JWT validation at ingress (OAuth2 Proxy), Dapr access control policies between services, mTLS verification.

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
