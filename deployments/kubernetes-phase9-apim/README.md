# Phase 9: Azure API Management with Dapr

Add Azure API Management (APIM) with a self-hosted gateway to the AKS deployment. The gateway runs inside the cluster with a Dapr sidecar, using Dapr service invocation to route requests to backend services.

> **Note**: These instructions use bash (Linux/macOS/WSL2). Run them from a Linux terminal.

**Teaching Points:**
- "Enterprise API gateway capabilities (caching, rate limiting, API versioning) with Dapr's service mesh — the gateway becomes just another Dapr-enabled app."
- "Extend an existing deployment without rebuilding — layer new infrastructure (APIM) onto a running system."

## Why APIM Instead of nginx-ingress?

Both nginx-ingress (Phase 6-8) and APIM gateway serve the same core role: L7 routing with a Dapr sidecar for service invocation. The difference is what happens before the request reaches Dapr:

| Feature | nginx-ingress | APIM Gateway |
|---------|---------------|--------------|
| Path-based routing | Yes | Yes |
| Dapr service invocation | Yes (via sidecar) | Yes (via sidecar) |
| Response caching | No | Yes (60s configurable) |
| Rate limiting | Basic (per-IP) | Advanced (per-key, per-API) |
| Request validation | No | Yes (JSON schema, size limits) |
| API subscriptions/keys | No | Yes (X-API-Key header) |
| Analytics & monitoring | Basic logs | Azure Portal dashboard |
| Developer portal | No | Yes (auto-generated API docs) |

For simple routing, nginx-ingress is sufficient. APIM adds enterprise API management when you need to control, monitor, and monetize your APIs.

## Prerequisites

> **Different Pattern:** Phases 3-8 each deploy a complete system from scratch. Phase 9 demonstrates a different pattern: **extending an existing deployment** with new capabilities. This is how you'd add APIM to a production system — you don't rebuild everything, you layer on new infrastructure. Deploy Phase 6, 7, or 8 first, then add Phase 9 on top.

### Existing Infrastructure Required

- AKS cluster running (from Phase 6, 7, or 8)
- Dapr installed on the cluster
- Backend services deployed (catalog-service, order-service, workflow-service)
- Resource group exists in Azure

### Tools

- Azure CLI: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
- Terraform: [Install guide](https://developer.hashicorp.com/terraform/install)
- kubectl: `az aks install-cli`
- jq: `sudo apt-get install -y jq`
- Azure subscription with permissions to create APIM resources

### Cost

- APIM Developer SKU: ~$50/month (in addition to existing AKS costs)

Remember to run `./scripts/cleanup.sh` or `terraform destroy` when not using.

## Architecture

APIM self-hosted gateway runs in AKS with its own Azure Load Balancer (not through nginx-ingress). The gateway has a Dapr sidecar for service invocation.

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                     AKS Cluster                         │
                                    │                                                         │
Internet ──▶ Azure Load Balancer ──▶│  APIM Gateway (type: LoadBalancer)                     │
             (L4, auto-provisioned) │  + Dapr sidecar (app-id: apim-gateway)                 │
                                    │        │                                                │
                                    │        │ localhost:3500/v1.0/invoke/{service}/method/  │
                                    │        │                                                │
                                    │        ├──▶ catalog-service (cached, public)           │
                                    │        ├──▶ order-service (auth required)              │
                                    │        └──▶ workflow-service (auth required)           │
                                    │                                                         │
                                    └─────────────────────────────────────────────────────────┘
```

**Key difference from Phase 6-8:** APIM gets its own public IP via `service.type: LoadBalancer`. It does not go through nginx-ingress. This gives you two public endpoints:
- Web app: `http://dapr-demo.{region}.cloudapp.azure.com/` (nginx-ingress)
- API: `http://dapr-demo-api.{region}.cloudapp.azure.com/api/v1/...` (APIM)

## API Surface

| Method | Endpoint | Backend | Policies |
|--------|----------|---------|----------|
| `GET` | `/api/v1/catalog` | catalog-service | Cache 60s, Rate limit 1000/min, Public |
| `GET` | `/api/v1/catalog/{id}` | catalog-service | Cache 60s, Rate limit 1000/min, Public |
| `POST` | `/api/v1/orders` | workflow-service | Auth, Rate limit 100/min, Validation |
| `GET` | `/api/v1/orders/{id}` | workflow-service | Auth, Rate limit 500/min |
| `GET` | `/api/v1/orders` | order-service | Auth, Rate limit 500/min |

## Quick Start

```bash
# 0. First deploy Phase 6, 7, or 8 to get AKS cluster + services running
#    (Phase 9 adds APIM on top of an existing deployment)

cd deployments/kubernetes-phase9-apim

# 1. Verify AKS cluster and services are running
export KUBECONFIG=/mnt/c/Users/<username>/.kube/config
kubectl get nodes
kubectl get pods -n dapr-demo  # Should show catalog, order, workflow services

# 2. Provision APIM (takes 15-30 minutes)
cd terraform
terraform init
terraform apply
cd ..

# 3. Deploy self-hosted gateway to AKS
./scripts/deploy-gateway.sh

# 4. Configure APIs and policies
./scripts/configure-apis.sh

# 5. Test
./scripts/test-apim.sh
```

## What APIM Adds

### 1. Caching
Catalog endpoints are cached for 60 seconds. Repeated requests hit the cache instead of the backend service.

### 2. Rate Limiting
- Catalog: 1000 requests/minute (public, generous)
- Orders: 100-500 requests/minute (authenticated)

Exceeding limits returns 429 Too Many Requests.

### 3. API Versioning
All endpoints are versioned under `/api/v1/`. A future `/api/v2/` could route to different services without client changes.

### 4. Authentication
Orders endpoints require an API subscription key (`X-API-Key` header). Catalog is public.

### 5. Request Validation
`POST /orders` validates the request body schema before forwarding to the workflow service.

## How Dapr Integration Works

The self-hosted gateway runs as a Kubernetes deployment with Dapr sidecar annotations:

```yaml
annotations:
  dapr.io/enabled: "true"
  dapr.io/app-id: "apim-gateway"
  dapr.io/app-port: "8080"
```

APIM policies use `set-backend-service` with Dapr:

```xml
<set-backend-service backend-id="dapr"
                    dapr-app-id="catalog-service"
                    dapr-method="products" />
```

This tells APIM to route the request through its Dapr sidecar using service invocation, which then uses Dapr's service discovery and mTLS to reach the target service.

## Files

```
kubernetes-phase9-apim/
├── README.md
├── terraform/
│   ├── main.tf              # Resource group reference
│   ├── apim.tf              # APIM instance + self-hosted gateway
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Gateway config endpoint, token
│   └── providers.tf         # Azure provider
├── scripts/
│   ├── deploy-gateway.sh    # Deploy gateway to AKS
│   ├── configure-apis.sh    # Configure APIs and policies
│   ├── test-apim.sh         # Test all endpoints
│   └── cleanup.sh           # Remove APIM resources
├── k8s/
│   └── apim-gateway.yaml    # Gateway deployment with Dapr
├── policies/
│   ├── global-policy.xml    # CORS, error handling
│   ├── catalog-policy.xml   # Caching, rate limiting
│   └── orders-policy.xml    # Auth, rate limiting, validation
└── api-definitions/
    ├── catalog-api.yaml     # OpenAPI spec
    └── orders-api.yaml      # OpenAPI spec
```

## Costs

- APIM Developer SKU: ~$50/month
- Self-hosted gateway: No additional cost (runs in your AKS)

Remember to run `./scripts/cleanup.sh` or `terraform destroy` when not using.

## Cleanup

```bash
./scripts/cleanup.sh
# Or manually:
cd terraform && terraform destroy
```
