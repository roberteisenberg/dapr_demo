# Phase 10: CI/CD + Developer Experience

Automated build and deployment pipeline via GitHub Actions, plus VS Code debugging configurations for local development with Dapr sidecars.

> **Note**: Phase 10 does not deploy new services or infrastructure. It adds automation and developer tooling on top of the existing AKS + APIM deployment from Phases 6-9.

**Teaching Points:**
- "CI/CD for microservices — build all services in parallel, deploy together, smoke test through the API gateway."
- "VS Code debug configs that start Dapr sidecars automatically — the same sidecar pattern used in production, running on your laptop."

## What Phase 10 Adds

### 1. GitHub Actions Pipeline (`.github/workflows/deploy.yml`)

Triggered manually via `workflow_dispatch` — from the GitHub Actions UI or CLI. This avoids accidental builds when learners working through earlier phases push service code changes.

```
Manual trigger (workflow_dispatch)
    ↓
┌─────────────────────────────────────┐
│  Build (matrix, 5 in parallel)      │
│  catalog / order / notification /   │
│  workflow / web-app                 │
│  → Docker Hub: reisenberg100/dapr-* │
└─────────────┬───────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  Deploy to AKS                      │
│  kubectl rollout restart (all 5)    │
│  kubectl rollout status (wait)      │
└─────────────┬───────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  Smoke Test via APIM                │
│  GET /api/v1/catalog → 200          │
│  GET /api/v1/orders  → 401          │
└─────────────────────────────────────┘
```

### 2. VS Code Debug Configs (`.vscode/`)

Debug any backend service with a Dapr sidecar started automatically:

| Config | Language | Port | Dapr Port |
|--------|----------|------|-----------|
| Debug Catalog Service | Go | 8080 | 3500 |
| Debug Order Service | Python | 8081 | 3501 |
| Debug Notification Service | Node.js | 8082 | 3502 |
| Debug Workflow Service | .NET | 8083 | 3503 |
| Debug All Services | (compound) | all | all |

## Prerequisites

### For CI/CD

- GitHub repository with Actions enabled
- Docker Hub account with access token
- Azure service principal for AKS access
- AKS cluster running (Phase 6+)
- APIM gateway configured (Phase 9)

### For VS Code Debugging

- Dapr CLI installed (`dapr init`)
- Redis running locally (default Dapr state store / pub/sub)
- Language toolchains: Go, Python 3, Node.js, .NET 8 SDK
- VS Code extensions (recommended automatically via `.vscode/extensions.json`)

## Setup: GitHub Actions

### 1. Create Azure Service Principal

```bash
az ad sp create-for-rbac \
  --name "github-actions-dapr-demo" \
  --role contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/rg-dapr-demo \
  --sdk-auth
```

Copy the JSON output — this is your `AZURE_CREDENTIALS` secret.

### 2. Configure GitHub Secrets

Go to your repository → Settings → Secrets and variables → Actions, and add:

| Secret | Value |
|--------|-------|
| `DOCKERHUB_USERNAME` | `reisenberg100` |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `AZURE_CREDENTIALS` | JSON from step 1 |
| `AKS_RESOURCE_GROUP` | `rg-dapr-demo` |
| `AKS_CLUSTER_NAME` | `aks-dapr-demo` |
| `APIM_GATEWAY_URL` | `https://dapr-demo-apim.azure-api.net` |

### 3. Run the Pipeline

The pipeline is manual-only. Trigger it from the GitHub UI or CLI:

```bash
# From GitHub UI: Actions → Build & Deploy to AKS → Run workflow

# Or from CLI:
gh workflow run deploy.yml
```

Monitor at: `https://github.com/<owner>/dapr_demo/actions`

## Setup: VS Code Debugging

### 1. Install Extensions

Open the project in VS Code — you'll be prompted to install recommended extensions.

### 2. Start Redis

```bash
# Dapr's local components use Redis for state store and pub/sub
docker run -d --name redis -p 6379:6379 redis:7
```

### 3. Debug a Service

1. Open the Run and Debug panel (Ctrl+Shift+D)
2. Select a configuration (e.g., "Debug Catalog Service (Go)")
3. Press F5

The pre-launch task starts `daprd` with the correct app-id and ports. Set breakpoints in the service code, then call the Dapr API:

```bash
# Catalog service (Dapr sidecar on port 3500)
curl http://localhost:3500/v1.0/invoke/catalog-service/method/products

# Order service (Dapr sidecar on port 3501)
curl http://localhost:3501/v1.0/invoke/order-service/method/orders
```

### 4. Debug All Services

Select "Debug All Services" to launch all four backend services simultaneously, each with its own Dapr sidecar.

## How Deployment Works

The pipeline uses `kubectl rollout restart` rather than updating image tags in manifests. This works because all Kubernetes deployments use `imagePullPolicy: Always` with the `:latest` tag. The flow:

1. **Build**: Docker builds each service image and pushes to Docker Hub with `:latest` and `:<sha>` tags
2. **Deploy**: `kubectl rollout restart` creates new pods that pull the latest image
3. **Verify**: `kubectl rollout status` waits for all pods to be ready (5-minute timeout per service)
4. **Smoke test**: Curls the APIM gateway to verify end-to-end routing

### Why Not Update Image Tags?

Updating manifests with a specific SHA tag is more production-appropriate, but:
- It requires re-applying manifests or using `kubectl set image`
- The demo manifests are in phase-specific directories (Phase 6, 7, 8) — the pipeline doesn't know which phase is deployed
- `rollout restart` is simpler and works regardless of which phase's manifests are active

## Files

```
Phase 10 files (distributed across the repo):
├── .github/workflows/
│   └── deploy.yml              # CI/CD pipeline
├── .vscode/
│   ├── extensions.json         # Recommended extensions
│   ├── launch.json             # Debug configurations
│   └── tasks.json              # Dapr sidecar tasks
└── deployments/kubernetes-phase10-cicd/
    ├── README.md               # This file
    ├── ARCHITECTURE.md         # Detailed architecture
    └── scripts/
        └── smoke-test-apim.sh  # Smoke test for pipeline
```

## Troubleshooting

### Pipeline: Docker Build Fails

```bash
# Check Dockerfile builds locally
docker build -t test services/catalog-service
```

### Pipeline: Deploy Fails with Auth Error

The service principal may have expired or lack permissions:

```bash
# Verify service principal
az ad sp list --display-name github-actions-dapr-demo --output table

# Re-create if needed
az ad sp create-for-rbac --name "github-actions-dapr-demo" \
  --role contributor \
  --scopes /subscriptions/<sub-id>/resourceGroups/rg-dapr-demo \
  --sdk-auth
```

### VS Code: Dapr Sidecar Fails to Start

```bash
# Check Dapr is installed
dapr --version

# Initialize Dapr (installs default components)
dapr init

# Check Redis is running
docker ps | grep redis
```

### VS Code: "Debug All" Only Starts Some Services

Services may fail if ports conflict. Check that no services are already running:

```bash
# Kill any leftover daprd processes
pkill -f daprd

# Check ports
lsof -i :8080 -i :8081 -i :8082 -i :8083
```
