# Project Roadmap

---
## ⚠️ PENDING CHANGES - TEST BEFORE AKS

**Status:** Uncommitted changes need testing before proceeding to Phase 6 (AKS).

### Changes to Test:

1. **Fix: Ingress sidecar startup issue** (Phases 3, 4, 5)
   - `setup-cluster.sh` now creates tracing config before installing nginx-ingress
   - This prevents CrashLoopBackOff on the ingress controller's Dapr sidecar
   - **Test:** Run `minikube delete`, then full setup from scratch

2. **Fix: Port-forward cleanup** (Phases 3, 4, 5)
   - `cleanup.sh` now kills existing port-forwards
   - **Test:** Run `./scripts/cleanup.sh` and verify no orphan processes

3. **Feature: Web-app workflow integration** (Phase 5 only)
   - New "Workflow Order" button in React frontend
   - Shows saga steps visually (Validate → Reserve → Payment → Notify)
   - Shows compensation when payment fails (orders > $10k)
   - **Test:**
     ```bash
     ./scripts/build-images.sh --with-frontend
     ./scripts/deploy-all.sh --with-frontend
     # Click "Workflow Order" on a product, complete the form
     # Test success case (< $10k) and failure case (> $10k)
     ```

### After Testing:
```bash
git add -A
git commit -m "Fix ingress sidecar startup, add workflow UI integration"
```

Then proceed to Phase 6 (AKS).

---

## Overview

This project demonstrates Dapr microservices across deployment environments, progressing from local development to production-ready Kubernetes.

Each deployment type includes a sub-phase demonstrating **infrastructure portability** - switching pub/sub from Redis to RabbitMQ without code changes.

## Phase Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Local Development | Available |
| 1-A | Local: Redis → RabbitMQ | Available |
| 2 | Docker Compose | Available |
| 2-A | Docker: Redis → RabbitMQ | Available |
| 3 | Kubernetes Base | Available |
| 3-A | Kubernetes: Pub/Sub Redis → RabbitMQ | Available |
| 3-B | Kubernetes: State Redis → MongoDB | Available |
| 4 | Observability (Zipkin) | Available |
| 5 | Workflow (.NET Dapr Workflow) | Available |
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

**Location**: [deployments/docker/](deployments/docker/)

---

## Phase 2-A: Docker - Infrastructure Portability

Switch pub/sub from Redis to RabbitMQ in Docker environment.

---

## Phase 3: Kubernetes Base

Full Kubernetes deployment with minikube.

**What you'll learn:**
- Dapr on Kubernetes (automatic sidecar injection via annotations)
- NGINX Ingress with Dapr sidecar (API gateway pattern)
- Kubernetes manifests (Deployments, Services, Ingress)
- Building images for minikube's local Docker registry
- React web application frontend

**Location**: [deployments/kubernetes/](deployments/kubernetes/)

**Prerequisites:**
- Docker Desktop (running, WSL2 backend)
- minikube
- kubectl
- Dapr CLI
- Helm (for nginx-ingress)

### Implementation Notes

**Cluster setup:**
1. `minikube start --driver=docker --cpus=2 --memory=4096`
2. `dapr init -k` (installs Dapr control plane: operator, sentry, placement, dashboard)
3. Install nginx-ingress via Helm with Dapr sidecar annotations (API gateway pattern)

**Key architectural difference from Docker Compose:**
- No explicit sidecar containers - Dapr auto-injects via pod annotations:
  ```yaml
  annotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: "catalog-service"
    dapr.io/app-port: "8080"
  ```
- No Kubernetes Service objects needed for backend services (Dapr handles discovery)
- `imagePullPolicy: Never` (uses minikube's local Docker registry via `eval $(minikube docker-env)`)
- `dapr dashboard -k` works (full control plane available)

**Services to deploy:**
- The 3 core services from `services/` (same Dockerfiles as Docker Compose)
- React web-app frontend (new - needs `frontend/web-app/` with Dockerfile)
- NGINX Ingress controller with Dapr sidecar as API gateway

**Ingress routing pattern:**
- `/v1.0/*` → Dapr sidecar on ingress controller (service invocation API)
- `/*` → web-app (React frontend)

**Infrastructure:**
- Redis (state store + pub/sub) - deployed as K8s Deployment+Service
- Dapr components as K8s manifests (with namespace: dapr-demo)

**Manifest numbering convention (from old project):**
```
manifests/
├── 00-namespace.yaml
├── 01-redis.yaml
├── 02-rabbitmq.yaml           # Phase 3-A
├── 02-mongodb.yaml            # Phase 3-B
├── 03-components/
│   ├── statestore.yaml        # Redis (default)
│   ├── pubsub.yaml            # Redis (default)
│   └── templates/
│       ├── pubsub-redis.yaml
│       ├── pubsub-rabbitmq.yaml
│       ├── statestore-redis.yaml
│       └── statestore-mongodb.yaml
├── 04-catalog-service.yaml
├── 05-order-service.yaml
├── 06-notification-service.yaml
├── 08-web-app.yaml
└── 09-ingress.yaml
```

**Scripts needed:**
- `scripts/setup-cluster.sh` - Start minikube, install Dapr, install nginx-ingress
- `scripts/build-images.sh` - Build all images in minikube's Docker env
- `scripts/deploy-all.sh` - Apply all manifests in order, wait for readiness
- `scripts/cleanup.sh` - Remove all K8s resources
- `scripts/test-services.sh` - Test via ingress endpoint

**Reference implementation:** `C:\Projects\dapr_20260102\deployments\kubernetes\`
(Caution: old project bundles Zipkin and workflow-service which belong to Phase 4 and 5 respectively)

**Transition from Docker Compose:**
```bash
cd deployments/docker
docker-compose down -v
```

---

## Phase 3-A: Kubernetes - Pub/Sub Portability

Switch pub/sub from Redis to RabbitMQ in Kubernetes without code changes.

**What you'll learn:**
- Dapr pub/sub component abstraction
- Swapping messaging infrastructure in Kubernetes

**How:**
```bash
# Deploy RabbitMQ
kubectl apply -f manifests/02-rabbitmq.yaml
kubectl wait --for=condition=available --timeout=300s deployment/rabbitmq -n dapr-demo

# Swap component
cp manifests/03-components/templates/pubsub-rabbitmq.yaml manifests/03-components/pubsub.yaml
kubectl apply -f manifests/03-components/

# Restart services to pick up new component
kubectl rollout restart deployment -n dapr-demo
```

---

## Phase 3-B: Kubernetes - State Store Portability

Switch state store from Redis to MongoDB in Kubernetes without code changes.

**What you'll learn:**
- Dapr state store component abstraction
- Swapping from a key-value store (Redis) to a document database (MongoDB) with zero code changes

**How:**
```bash
# Deploy MongoDB
kubectl apply -f manifests/02-mongodb.yaml
kubectl wait --for=condition=available --timeout=300s deployment/mongodb -n dapr-demo

# Swap component
cp manifests/03-components/templates/statestore-mongodb.yaml manifests/03-components/statestore.yaml
kubectl apply -f manifests/03-components/

# Restart services to pick up new component
kubectl rollout restart deployment -n dapr-demo
```

**Manifest templates needed:**
```
manifests/03-components/templates/
├── pubsub-redis.yaml
├── pubsub-rabbitmq.yaml
├── statestore-redis.yaml
└── statestore-mongodb.yaml
```

**MongoDB statestore component:**
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
  namespace: dapr-demo
spec:
  type: state.mongodb
  version: v1
  metadata:
  - name: host
    value: mongodb:27017
  - name: databaseName
    value: daprdb
  - name: actorStateStore
    value: "true"
```

---

## Phase 4: Observability

Add Zipkin distributed tracing to the Kubernetes deployment. Dapr sidecars automatically send trace spans to Zipkin, providing visibility into request flows across all services.

**What you'll learn:**
- Dapr tracing configuration
- Zipkin distributed tracing UI
- Visualizing request flows across microservices
- Debugging latency and errors in distributed systems

**Location**: [deployments/kubernetes-phase4-observability/](deployments/kubernetes-phase4-observability/)

**Key changes from Phase 3:**
- `manifests/10-zipkin.yaml` - Zipkin deployment
- `manifests/03-components/tracing.yaml` - Dapr tracing Configuration
- Service manifests add `dapr.io/config: "tracing"` annotation

**Dashboards available:**

| Dashboard | Command | URL |
|-----------|---------|-----|
| Zipkin | `kubectl port-forward -n dapr-demo svc/zipkin 9411:9411` | http://localhost:9411 |
| Dapr | `dapr dashboard -k -n dapr-demo` | http://localhost:8080 |
| Minikube | `minikube dashboard` | Opens automatically |

---

## Phase 5: Workflow

Add a .NET Dapr Workflow service for order orchestration using the saga pattern with automatic compensation on failure.

**What you'll learn:**
- Dapr Workflow SDK for .NET
- Saga pattern for distributed transactions
- Compensation logic for rollback
- Workflow state management

**Location**: [deployments/kubernetes-phase5-workflow/](deployments/kubernetes-phase5-workflow/)

**New service**: `services/workflow-service/` (.NET 8.0)

**Saga steps:**
1. ValidateOrderActivity - Validate order fields
2. ReserveInventoryActivity - Decrement stock (compensation: release)
3. ProcessPaymentActivity - Simulate payment (fails if >$10k)
4. NotifyCustomerActivity - Publish to pub/sub

**Key changes from Phase 4:**
- `services/workflow-service/` - New .NET 8.0 Dapr Workflow service
- `manifests/07-workflow-service.yaml` - Kubernetes deployment
- `scripts/test-workflow.sh` - Tests saga pattern and compensation

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
├── services/                      # Shared (Docker & Kubernetes)
│   ├── catalog-service/           # Go + Dockerfile
│   ├── order-service/             # Python + Dockerfile
│   ├── notification-service/      # Node.js + Dockerfile
│   └── workflow-service/          # .NET 8.0 + Dockerfile (Phase 5)
├── frontend/                      # Phase 3+ (Kubernetes only)
│   └── web-app/                   # React SPA + Dockerfile
└── deployments/
    ├── local/                     # Phase 1, 1-A
    │   ├── catalog-service/       # Embedded (no Dockerfile)
    │   ├── order-service/
    │   ├── notification-service/
    │   └── components/
    ├── docker/                    # Phase 2, 2-A
    │   ├── docker-compose.yml
    │   └── components/
    ├── kubernetes/                # Phase 3 (base)
    │   ├── manifests/
    │   ├── config/
    │   └── scripts/
    ├── kubernetes-phase4-observability/  # Phase 4 (adds Zipkin)
    │   ├── manifests/
    │   │   └── 10-zipkin.yaml
    │   │   └── 03-components/tracing.yaml
    │   ├── config/
    │   └── scripts/
    └── kubernetes-phase5-workflow/       # Phase 5 (adds Dapr Workflow)
        ├── manifests/
        │   └── 07-workflow-service.yaml
        ├── config/
        └── scripts/
            └── test-workflow.sh
```

### Why Embedded Services in Local?

Local deployment includes service source code directly because:
- Runs services from source (`dapr run`) - no Docker needed
- Self-contained - everything in one directory
- No Dockerfiles required

Docker and Kubernetes use a shared `services/` directory with Dockerfiles.
