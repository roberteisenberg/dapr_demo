# Project Roadmap

## Overview

This project demonstrates Dapr microservices across deployment environments, progressing from local development to production-ready Kubernetes.

Each deployment type includes a sub-phase demonstrating **infrastructure portability** - switching pub/sub from Redis to RabbitMQ without code changes.

## Phase Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Local Development | Available |
| 1-A | Local: Redis → RabbitMQ | Available |
| 2 | Docker Compose | Planned |
| 2-A | Docker: Redis → RabbitMQ | Planned |
| 3 | Kubernetes Base | Planned |
| 3-A | Kubernetes: Redis → RabbitMQ | Planned |
| 4 | Observability (Zipkin) | Planned |
| 5 | Workflow (.NET Dapr Workflow) | Planned |
| 6 | Cloud (Azure AKS) | Planned |
| 7 | Secrets (Azure Key Vault) | Planned |
| 8 | CI/CD (GitHub Actions) | Planned |
| 9 | API Management | Planned |

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

**Location**: deployments/docker/ (coming soon)

---

## Phase 2-A: Docker - Infrastructure Portability

Switch pub/sub from Redis to RabbitMQ in Docker environment.

---

## Phase 3: Kubernetes Base

Full Kubernetes deployment with minikube.

**What you'll learn:**
- Dapr on Kubernetes
- Automatic sidecar injection
- NGINX Ingress with Dapr sidecar (API gateway pattern)
- React web application frontend

**Location**: deployments/kubernetes/ (coming soon)

---

## Phase 3-A: Kubernetes - Infrastructure Portability

Switch pub/sub from Redis to RabbitMQ in Kubernetes.

---

## Phase 4: Observability

Add distributed tracing to the Kubernetes deployment.

**What you'll learn:**
- Zipkin distributed tracing
- Dapr dashboard
- Debugging microservices

---

## Phase 5: Workflow

Add a .NET Dapr Workflow service for order orchestration.

**What you'll learn:**
- Dapr Workflow SDK
- Saga pattern for distributed transactions
- Order fulfillment workflow with compensation

---

## Phase 6+: Cloud & Enterprise (Future)

| Phase | Feature | Description |
|-------|---------|-------------|
| 6 | Azure AKS | Deploy to Azure Kubernetes Service |
| 7 | Secrets | Azure Key Vault integration |
| 8 | CI/CD | GitHub Actions pipelines |
| 9 | API Management | Azure APIM gateway |

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
└── deployments/
    ├── local/                # Phase 1, 1-A
    │   ├── catalog-service/  # Embedded (no Dockerfile)
    │   ├── order-service/
    │   ├── notification-service/
    │   └── components/
    ├── docker/               # Phase 2, 2-A
    └── kubernetes/           # Phase 3+
```

### Why Embedded Services in Local?

Local deployment includes service source code directly because:
- Runs services from source (`dapr run`) - no Docker needed
- Self-contained - everything in one directory
- No Dockerfiles required

Docker and Kubernetes use a shared `services/` directory with Dockerfiles.
