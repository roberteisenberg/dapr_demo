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
| 7 | AI Integration (manual "Copy for AI") | Available |
| 7-A | AI Fraud Check in Order Workflow | Available |
| 8 | End-to-end Security | Available |
| 9 | API Management | Available |
| 10 | CI/CD + Developer Experience | Available |
| 11 | Resilience | Planned |
| 12 | Actors | Planned |
| 13 | Runtime Flexibility | Planned |
| 14 | Multi-Cloud Integration | Planned |
| 15 | Cloud Portability | Planned |

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

## Phase 7: AI Integration (Manual) + Order Lifecycle

"Copy for AI" button exports pending orders for fraud review in Claude Desktop. Orders panel with Ship/Cancel buttons. Cancel restores inventory.

**What you'll learn:**
- Exporting business data as a structured AI prompt for fraud review
- Order lifecycle: pending_shipment → shipped/cancelled
- Inventory restoration on cancellation (same pattern as saga compensation)

**Location**: [deployments/kubernetes-phase7-ai/](deployments/kubernetes-phase7-ai/)

---

## Phase 7-A: AI Fraud Scoring in Order Workflow

Add an AI-powered fraud scoring step to the order fulfillment saga. `CheckFraudActivity` calls Claude via the Dapr Conversation API to score each order's risk (0-100) before payment. Orders scoring >= 80 are rejected. `RecordOrderActivity` saves approved orders to the state store as "pending_shipment" with their fraud score.

**What you'll learn:**
- Adding an LLM call to a deterministic Dapr Workflow
- Score-based AI assessment (0-100) — humans set the threshold, not the LLM
- Dapr Conversation API — provider-agnostic LLM abstraction
- API key management via Kubernetes secrets + Dapr `secretKeyRef`
- Graceful degradation when AI is unavailable

**Saga steps (updated from Phase 5):**
1. ValidateOrderActivity
2. ReserveInventoryActivity
3. CheckFraudActivity (NEW — fraud score 0-100 via Dapr Conversation API → Claude)
4. ProcessPaymentActivity
5. NotifyCustomerActivity
6. RecordOrderActivity (NEW — saves to order-service state store)

**Location**: [deployments/kubernetes-phase7-ai/](deployments/kubernetes-phase7-ai/)

---

## Phase 8: End-to-End Security

End-to-end security layered onto the AKS deployment. Five security layers: TLS via Let's Encrypt (cert-manager), Azure AD login in the React app (MSAL.js with PKCE), JWT validation at the ingress (OAuth2 Proxy), Dapr mTLS between sidecars, and Dapr access control policies restricting inter-service calls.

**What you'll learn:**
- TLS with cert-manager and Let's Encrypt (required for MSAL.js `crypto.subtle`)
- Azure AD (Entra ID) authentication with MSAL.js in a React SPA (Authorization Code + PKCE)
- OAuth2 Proxy for JWT validation as an NGINX ingress subrequest
- Dapr access control policies (allowlist per app-id)
- Runtime configuration via Kubernetes ConfigMaps (no image rebuild per environment)
- Automated Azure AD app registration via Microsoft Graph API
- Dapr mTLS verification

**Location**: [deployments/kubernetes-phase8-security/](deployments/kubernetes-phase8-security/)

---

## Phase 9: API Management

Add Azure API Management (APIM) to the AKS deployment. APIM's cloud gateway applies enterprise policies (caching, rate limiting, subscriptions, validation), then routes through nginx-ingress to reach backend services via Dapr service invocation.

**What you'll learn:**
- APIM cloud gateway routing through nginx-ingress (Developer SKU cost-effective pattern)
- Response caching, rate limiting, request validation via APIM policies
- API versioning and subscription keys
- Extending an existing deployment without rebuilding — layer APIM onto a running system

**Location**: [deployments/kubernetes-phase9-apim/](deployments/kubernetes-phase9-apim/)

---

## Phase 10: CI/CD + Developer Experience

GitHub Actions pipeline for automated build, deploy, and smoke test. VS Code debugging configuration for developing services locally with Dapr sidecars.

**What you'll learn:**
- GitHub Actions CI/CD — matrix build (5 services in parallel), deploy to AKS, smoke test through APIM
- VS Code debug configs with automatic Dapr sidecar startup (`daprd` as pre-launch tasks)
- Path-filtered triggers (only service code changes trigger builds)
- Compound debugging (all 4 backend services + Dapr sidecars simultaneously)

**Location**: [deployments/kubernetes-phase10-cicd/](deployments/kubernetes-phase10-cicd/) + [.github/workflows/](.github/workflows/) + [.vscode/](.vscode/)

---

## Phase 11: Resilience

Production-harden the application with Dapr resiliency policies, pub/sub dead letter handling, and horizontal pod autoscaling under load. All visible through Phase 4's Zipkin tracing.

**What you'll learn:**
- Dapr resiliency policies — retries with exponential backoff, timeouts, circuit breakers (one YAML file, zero code changes)
- Pub/sub dead letter topics — failed messages routed to a dead letter topic instead of lost
- Horizontal Pod Autoscaler (HPA) with load testing (k6 or hey) and Zipkin visualization of scaling behavior

**Demo walkthrough:** Kill a service → circuit breaker trips → retries succeed when it recovers. Poison a pub/sub message → dead letter catches it. Flood requests → pods scale up → traces stay healthy.

---

## Phase 12: Actors

Replace direct state store operations for inventory with Dapr virtual actors. Each product becomes an actor managing its own stock, eliminating concurrency issues with competing orders.

**What you'll learn:**
- Dapr virtual actor pattern for stateful, concurrent entities
- Actor-based inventory management (turn-based access eliminates race conditions)
- The same actor model that powers Dapr Workflow internally and Dapr Agents' `DurableAgent` for scalable AI

---

## Phase 13: Runtime Flexibility

Change application behavior at runtime without redeployment. Feature flags via the Dapr Configuration API and scheduled background tasks via Dapr Jobs or cron bindings.

**What you'll learn:**
- Dapr Configuration API for feature flags (toggle fraud check, maintenance mode) backed by Redis
- Dapr cron binding or Jobs API for scheduled tasks (inventory reports, stale order cleanup)
- Input bindings (not covered elsewhere in the project)

---

## Phase 14: Multi-Cloud Integration

Extend the AKS deployment to interact with services and storage on AWS. Cross-cloud calls go through Dapr bindings and service invocation — the application code has no cloud-specific imports.

**What you'll learn:**
- Dapr output/input bindings (AWS S3 for fraud document storage)
- Dapr service invocation for external HTTP endpoints (`HTTPEndpoint`) — no Dapr sidecar needed on the target
- Cross-cloud secret management (Azure Key Vault storing AWS credentials, accessed via Dapr secret store)
- Cross-cloud observability — Zipkin traces spanning Azure and AWS calls
- Dapr resiliency policies applied to cross-cloud calls automatically

---

## Phase 15: Cloud Portability

Deploy the entire application to AWS EKS with Terraform. Service code, Dapr component YAMLs, and Kubernetes manifests stay unchanged. Only the Terraform and cloud-specific configuration change.

**What you'll learn:**
- Three tiers of cloud portability: Dapr abstractions (swap a YAML), cloud infrastructure (different Terraform), and proprietary dependencies (APIM — rearchitect)
- EKS cluster provisioning with Terraform
- The real cost of vendor lock-in — contrast "swap Redis for RabbitMQ in 30 seconds" with "migrate APIM to AWS API Gateway over weeks"

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
├── .github/workflows/             # Phase 10: CI/CD pipeline
│   └── deploy.yml
├── .vscode/                       # Phase 10: Debug configs
│   ├── launch.json
│   ├── tasks.json
│   └── extensions.json
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
    ├── kubernetes-phase6-aks/
    │   ├── terraform/             # AKS + Resource Group
    │   ├── manifests/
    │   ├── config/
    │   ├── docs/                  # Screenshots
    │   └── scripts/
    ├── kubernetes-phase7-ai/
    ├── kubernetes-phase8-security/
    │   ├── terraform/             # AKS (same as Phase 6)
    │   ├── manifests/             # + OAuth2 Proxy, TLS ingress
    │   ├── config/                # ingress-values.yaml
    │   └── scripts/               # + setup with cert-manager & Azure AD
    ├── kubernetes-phase9-apim/
    │   ├── terraform/             # APIM instance (Developer SKU)
    │   ├── k8s/                   # APIM ingress rule
    │   ├── policies/              # APIM policies (caching, rate limiting)
    │   ├── api-definitions/       # OpenAPI specs
    │   └── scripts/
    └── kubernetes-phase10-cicd/
        ├── README.md              # CI/CD documentation
        ├── ARCHITECTURE.md        # Architecture details
        └── scripts/
            └── smoke-test-apim.sh # Pipeline smoke test
```
