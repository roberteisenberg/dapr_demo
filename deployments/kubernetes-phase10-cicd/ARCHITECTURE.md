# Phase 10: CI/CD + Developer Experience Architecture

## Overview

Phase 10 adds two capabilities to the project: a GitHub Actions pipeline for deploying to the AKS + APIM stack (triggered manually via `workflow_dispatch`), and VS Code configurations for local debugging with Dapr sidecars.

Neither capability introduces new services or infrastructure. They operate on the existing system built in Phases 1-9.

## CI/CD Pipeline Architecture

### Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GitHub Actions                                 │
│                                                                         │
│  Trigger: manual dispatch (workflow_dispatch)                          │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  Job 1: build-and-push (matrix, 5 parallel runners)              │ │
│  │                                                                   │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────┐ │ │
│  │  │ catalog  │ │ order    │ │ notif.   │ │ workflow │ │web-app│ │ │
│  │  │ Go       │ │ Python   │ │ Node.js  │ │ .NET     │ │ React │ │ │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬───┘ │ │
│  │       └──────────┬──┴───────────┬┴────────────┴───────────┘     │ │
│  │                  ▼                                               │ │
│  │        Docker Hub (reisenberg100/dapr-*)                        │ │
│  │        Tags: :latest + :<sha>                                    │ │
│  └──────────────────┬────────────────────────────────────────────────┘ │
│                     ▼                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  Job 2: deploy                                                    │ │
│  │                                                                   │ │
│  │  az login → az aks get-credentials                               │ │
│  │  kubectl rollout restart (all 5 deployments)                     │ │
│  │  kubectl rollout status (wait, 5min timeout each)                │ │
│  └──────────────────┬────────────────────────────────────────────────┘ │
│                     ▼                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  Job 3: smoke-test                                                │ │
│  │                                                                   │ │
│  │  GET /api/v1/catalog → expect 200 (public endpoint)              │ │
│  │  GET /api/v1/orders  → expect 401 (no API key)                   │ │
│  └───────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### Design Decisions

#### Single Workflow with Matrix vs. Per-Service Workflows

A single workflow with a build matrix keeps the demo simple. All services are built in parallel (5 runners), then deployed together. Per-service workflows would allow independent deployment but add complexity (service dependency ordering, partial deploys).

#### Docker Hub vs. ACR

The project already uses Docker Hub (`reisenberg100/dapr-*`). Migrating to Azure Container Registry would add Terraform changes, image pull secrets, and AKS-ACR integration. Not worth the complexity for a demo.

#### `kubectl rollout restart` vs. Image Tag Updates

The Kubernetes manifests use `imagePullPolicy: Always` with `:latest` tags. `kubectl rollout restart` creates new pods that pull the latest image. This is simpler than:
- Using `kubectl set image` (would need to know the exact container name in each deployment)
- Re-applying manifests with a new tag (the pipeline doesn't know which phase's manifests are deployed)

The tradeoff: you can't roll back to a specific version via kubectl. For a demo, this is acceptable. In production, you'd pin image tags and use a GitOps tool like Flux or ArgoCD.

#### Manual Trigger Only

The workflow uses `workflow_dispatch` (manual trigger) rather than automatic push triggers. This is intentional — the repository is a phased learning project, and learners working through earlier phases (1-9) would otherwise trigger expensive Azure builds when pushing service code changes. Deployments should be deliberate: trigger from the GitHub Actions UI or via `gh workflow run deploy.yml`.

### Secrets

| Secret | Purpose | How to Create |
|--------|---------|---------------|
| `DOCKERHUB_USERNAME` | Docker Hub login | Docker Hub → Account Settings → Security |
| `DOCKERHUB_TOKEN` | Docker Hub auth | Docker Hub → Account Settings → Access Tokens |
| `AZURE_CREDENTIALS` | Azure login | `az ad sp create-for-rbac --sdk-auth` |
| `AKS_RESOURCE_GROUP` | AKS cluster location | From Terraform: `rg-dapr-demo` |
| `AKS_CLUSTER_NAME` | AKS cluster name | From Terraform: `aks-dapr-demo` |
| `APIM_GATEWAY_URL` | Smoke test target | From Terraform: `https://dapr-demo-apim.azure-api.net` |

### Smoke Test

The smoke test validates two things:

1. **End-to-end routing works**: `GET /api/v1/catalog` returns 200 — proves APIM → nginx-ingress → Dapr → catalog-service chain is functional
2. **APIM policies are enforced**: `GET /api/v1/orders` returns 401 without an API key — proves subscription key enforcement is active

These two checks cover the entire request path. If both pass, the deployment is healthy.

## VS Code Debug Architecture

### Sidecar Pattern

Each debug configuration starts a `daprd` sidecar process alongside the service, mirroring the Kubernetes sidecar injection pattern:

```
VS Code Debug Session
│
├── Service Process (with debugger attached)
│   └── Listens on app port (8080, 8081, 8082, or 8083)
│
└── daprd Process (background task)
    ├── Listens on HTTP port (3500, 3501, 3502, or 3503)
    ├── Listens on gRPC port (50001, 50002, 50003, or 50004)
    └── Uses components from deployments/local/components/
```

### Port Assignment

Each service has unique ports to allow running simultaneously:

| Service | App Port | Dapr HTTP | Dapr gRPC |
|---------|----------|-----------|-----------|
| catalog-service | 8080 | 3500 | 50001 |
| order-service | 8081 | 3501 | 50002 |
| notification-service | 8082 | 3502 | 50003 |
| workflow-service | 8083 | 3503 | 50004 |

These match the `deployments/local/dapr.yaml` configuration used for `dapr run -f`.

### Task Lifecycle

1. **Pre-launch task** (`start-dapr-{service}`): Starts `daprd` as a background process with `isBackground: true`. The problem matcher waits for "dapr initialized" before continuing.
2. **Debug session**: VS Code attaches the debugger to the service process. Set breakpoints, inspect variables, step through code.
3. **Post-debug task** (`stop-all-dapr`): Kills all `daprd` processes to clean up.

### "Debug All Services" Compound

The compound configuration launches all four services simultaneously. Each gets its own `daprd` sidecar on separate ports. Services can communicate via Dapr service invocation (e.g., the order service calls the catalog service through `localhost:3501/v1.0/invoke/catalog-service/method/products`).

## What's Not Automated

| Item | Why Manual |
|------|-----------|
| Terraform (AKS, APIM) | Infrastructure changes are infrequent and high-impact — better reviewed manually |
| Dapr installation | One-time setup, version-pinned |
| cert-manager, OAuth2 Proxy | Security infrastructure — manual review preferred |
| GitHub secrets | Must be configured once per repository |
