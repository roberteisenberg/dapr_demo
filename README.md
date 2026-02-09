# Dapr Microservices Demo

A hands-on project demonstrating Dapr microservices from local development to cloud-ready Kubernetes — covering Infrastructure as Code, distributed workflows, and AI-powered fraud detection utilizing Dapr workflow to call the Claude API.

**[Dapr](https://dapr.io/)** (Distributed Application Runtime) is a runtime that simplifies building microservices. It runs as a "sidecar" process alongside each service, providing built-in capabilities — state management, messaging, service discovery, retries, observability — through a simple HTTP/gRPC API. Your code talks to `localhost:3500` and Dapr handles the rest. Swap Redis for RabbitMQ by changing a YAML file, not your code.

**[Kubernetes](https://kubernetes.io/)** is a container orchestration platform originally developed by Google to manage its massive data center infrastructure, then open-sourced in 2014. It has since become the industry standard for deploying and scaling containerized applications. This project starts without it (Phases 1–2) so you can see Dapr's value before Kubernetes enters the picture in Phase 3. Dapr and Kubernetes are both [CNCF](https://www.cncf.io/) projects. Rather than reinventing the wheel, Dapr leverages established Kubernetes primitives — annotations for sidecar injection, CRDs for component configuration, Helm for installation — while adding application-level concerns like state, messaging, and service invocation on top.

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
- **API Management**: Azure APIM self-hosted gateway with Dapr service invocation
- **Resiliency**: Retries, timeouts, circuit breakers, dead letter topics
- **Virtual Actors**: Dapr Actors for concurrent inventory management
- **Runtime Configuration**: Feature flags via Dapr Configuration API, scheduled tasks
- **CI/CD**: GitHub Actions pipelines, VS Code debugging with Dapr sidecars
- **Multi-Cloud**: Cross-cloud bindings and service invocation (AWS S3, external HTTP endpoints)
- **Cloud Portability**: Deploy the same application to AWS EKS

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

See [ROADMAP.md](ROADMAP.md) for the full phase progression.

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
