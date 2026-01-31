# Project Roadmap

## Overview

This project demonstrates Dapr microservices across deployment environments, progressing from local development to production-ready cloud Kubernetes.

Each deployment type includes a sub-phase demonstrating **infrastructure portability** - switching pub/sub from Redis to RabbitMQ without code changes.

## Phase Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Local Development | Available |
| 1-A | Local: Redis → RabbitMQ | Available |
| 2 | Docker Compose | Available |
| 2-A | Docker: Redis → RabbitMQ | Available |
| 3 | Kubernetes Base + React Frontend with Status Panel | Available |
| 3-A | Kubernetes: Pub/Sub Redis → RabbitMQ | Available |
| 3-B | Kubernetes: State Redis → MongoDB | Available |
| 4 | Observability (Zipkin) | Available |
| 5 | Workflow (.NET Dapr Workflow) | Available |
| 6 | Cloud (Azure AKS) and Terraform | Available |
| 7 | AI Agents (Dapr Agents) | Planned |
| 8 | End-to-end Security | Planned |
| 9 | CI/CD (GitHub Actions) | Planned |
| 10 | API Management | Planned |

---

## Phase 1: Local Development

Run services directly from source using `dapr run`. No containers needed.

**What you'll learn:**
- Dapr CLI basics
- State management with Redis
- Service-to-service invocation
- Pub/sub messaging

**Location**: [deployments/local/](deployments/local/)

---

## Phase 1-A: Local - Infrastructure Portability

Switch pub/sub from Redis to RabbitMQ without changing code.

**What you'll learn:**
- Dapr's component abstraction
- Swapping infrastructure via YAML config

**How:**
```bash
docker run -d --name rabbitmq -p 5672:5672 rabbitmq:3
cp components/templates/pubsub-rabbitmq.yaml components/pubsub.yaml
dapr run -f .   # Same code, different infrastructure
```

---

## Phase 2: Docker Compose

Containerized deployment with Dapr sidecars.

**What you'll learn:**
- Dapr in containers
- Sidecar pattern with Docker Compose
- Container networking

**Location**: [deployments/docker/](deployments/docker/)

---

## Phase 2-A: Docker - Infrastructure Portability

Switch pub/sub from Redis to RabbitMQ in Docker environment.

---

## Phase 3: Kubernetes Base

Full Kubernetes deployment with minikube. Introduces the React web application with a real-time status panel that shows all Dapr operations as they happen.

**What you'll learn:**
- Dapr on Kubernetes (automatic sidecar injection via annotations)
- NGINX Ingress with Dapr sidecar (API gateway pattern)
- Kubernetes manifests (Deployments, Services, Ingress)
- React web application with Dapr activity monitoring

**Status Panel** (available in all Kubernetes phases):
- Axios interceptors capture every service invocation with timing and status codes
- **Activity tab**: Color-coded log (request/response/error) with duration (ms)
- **Services tab**: Detected services with request counts and health status

**Location**: [deployments/kubernetes/](deployments/kubernetes/)

---

## Phase 3-A: Kubernetes - Pub/Sub Portability

Switch pub/sub from Redis to RabbitMQ in Kubernetes without code changes.

**How:**
```bash
./scripts/deploy-all.sh --pubsub rabbitmq
```

---

## Phase 3-B: Kubernetes - State Store Portability

Switch state store from Redis to MongoDB in Kubernetes without code changes.

**How:**
```bash
./scripts/deploy-all.sh --statestore mongodb
```

---

## Phase 4: Observability

Add Zipkin distributed tracing to the Kubernetes deployment. Dapr sidecars automatically send trace spans to Zipkin, providing visibility into request flows across all services.

**What you'll learn:**
- Dapr tracing configuration
- Zipkin distributed tracing UI
- Visualizing request flows across microservices

**Location**: [deployments/kubernetes-phase4-observability/](deployments/kubernetes-phase4-observability/)

---

## Phase 5: Workflow

Add a .NET Dapr Workflow service for order orchestration using the saga pattern with automatic compensation on failure.

**What you'll learn:**
- Dapr Workflow SDK for .NET
- Saga pattern for distributed transactions
- Compensation logic for rollback

**Location**: [deployments/kubernetes-phase5-workflow/](deployments/kubernetes-phase5-workflow/)

**Saga steps:**
1. ValidateOrderActivity - Validate order fields
2. ReserveInventoryActivity - Decrement stock (compensation: release)
3. ProcessPaymentActivity - Simulate payment (fails if >$10k)
4. NotifyCustomerActivity - Publish to pub/sub

---

## Phase 6: Cloud (Azure AKS) and Terraform

Deploy to Azure Kubernetes Service with Terraform. Public access via Azure DNS label - no port-forward needed.

**What you'll learn:**
- Terraform for Azure infrastructure (AKS, Resource Group)
- AKS cluster creation and Dapr installation
- Public access patterns with LoadBalancer and DNS labels
- Persistent storage with Azure Managed Disks

**Location**: [deployments/kubernetes-phase6-aks/](deployments/kubernetes-phase6-aks/)

---

## Phase 7: AI Agents (Dapr Agents)

Build AI agents using **Dapr Agents** - an open source framework for durable, scalable AI agent orchestration.

**What you'll learn:**
- Dapr Agents framework for AI orchestration
- Durable agent execution (survives failures, resumes with context)
- Multi-agent systems with Pub/Sub mesh routing
- LLM provider abstraction (swap Claude ↔ OpenAI via YAML)

**New service:** `services/ai-agent-service/` (Python)

---

## Phase 8+: Future

| Phase | Feature | Description |
|-------|---------|-------------|
| 8 | End-to-end Security | React app to AKS with Azure AD, mTLS |
| 9 | CI/CD | GitHub Actions pipelines |
| 10 | API Management | Azure APIM gateway |

---

## Services

All phases use these three core services:

| Service | Language | Dapr Features |
|---------|----------|---------------|
| catalog-service | Go | State management |
| order-service | Python | Service invocation, Pub/sub, State |
| notification-service | Node.js | Pub/sub subscribe |

Additional services added in later phases:
- **web-app** (React) - Phase 3+
- **workflow-service** (.NET) - Phase 5+

---

## Directory Structure

```
dapr_demo/
├── README.md
├── ROADMAP.md
├── services/                      # Shared (Docker & Kubernetes)
│   ├── catalog-service/           # Go + Dockerfile
│   ├── order-service/             # Python + Dockerfile
│   ├── notification-service/      # Node.js + Dockerfile
│   └── workflow-service/          # .NET 8.0 + Dockerfile (Phase 5)
├── frontend/                      # Phase 3+ (Kubernetes only)
│   └── web-app/                   # React SPA + Dockerfile
└── deployments/
    ├── local/                     # Phase 1, 1-A
    ├── docker/                    # Phase 2, 2-A
    ├── kubernetes/                # Phase 3, 3-A, 3-B
    ├── kubernetes-phase4-observability/
    ├── kubernetes-phase5-workflow/
    └── kubernetes-phase6-aks/
        ├── terraform/             # AKS + Resource Group
        ├── manifests/
        ├── config/
        ├── docs/                  # Screenshots
        └── scripts/
```
