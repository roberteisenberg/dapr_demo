# Phase 9: Azure API Management with Dapr

Add Azure API Management (APIM) to the AKS deployment. APIM's cloud gateway applies enterprise policies (caching, rate limiting, subscriptions, validation), then routes through nginx-ingress to reach backend services via Dapr service invocation.

> **Note**: These instructions use bash (Linux/macOS/WSL2). Run them from a Linux terminal.

**Teaching Points:**
- "Enterprise API gateway capabilities (caching, rate limiting, API versioning) layered on top of Dapr's service mesh — APIM handles policy enforcement, Dapr handles service-to-service communication."
- "Extend an existing deployment without rebuilding — layer new infrastructure (APIM) onto a running system."

## Why APIM in Addition to nginx-ingress?

nginx-ingress (Phase 6-8) handles L7 routing and hosts the Dapr sidecar. APIM adds enterprise API management on top:

| Feature | nginx-ingress | APIM Cloud Gateway |
|---------|---------------|---------------------|
| Path-based routing | Yes | Yes |
| Dapr service invocation | Yes (via sidecar) | Via nginx-ingress |
| Response caching | No | Yes (60s configurable) |
| Rate limiting | Basic (per-IP) | Advanced (per-key, per-API) |
| Request validation | No | Yes (JSON schema, size limits) |
| API subscriptions/keys | No | Yes (X-API-Key header) |
| Analytics & monitoring | Basic logs | Azure Portal dashboard |
| Developer portal | No | Yes (auto-generated API docs) |

## Prerequisites

> **Different Pattern:** Phases 3-8 each deploy a complete system from scratch. Phase 9 demonstrates a different pattern: **extending an existing deployment** with new capabilities. Deploy Phase 6, 7, or 8 first, then add Phase 9 on top.

### Existing Infrastructure Required

- AKS cluster running (from Phase 6, 7, or 8)
- Dapr installed on the cluster
- Backend services deployed (catalog-service, order-service, workflow-service)
- nginx-ingress with Dapr sidecar (app-id: api-gateway)
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

APIM's cloud gateway (hosted in Azure) applies policies and routes requests through nginx-ingress in AKS. nginx-ingress has a Dapr sidecar that handles service invocation to backend services.

```
Internet → APIM Cloud Gateway (https://dapr-demo-apim.azure-api.net)
             applies: caching, rate limiting, subscriptions, validation
               ↓
           nginx-ingress in AKS (public FQDN, /apim/v1.0/* path)
             Dapr sidecar (app-id: api-gateway)
               ↓
           Backend services via Dapr service invocation (mTLS)
             ├── catalog-service
             ├── order-service
             └── workflow-service
```

**Key design decision:** The APIM Developer SKU does not support self-hosted gateways (the built-in managed gateway uses the single allowed gateway slot). Instead, the cloud gateway routes through the existing nginx-ingress, which already has a Dapr sidecar for service invocation. This preserves both APIM policy features and Dapr integration.

**How routing works:**
1. APIM cloud gateway receives `GET /api/v1/catalog`
2. APIM policies run (rate limit, cache lookup, etc.)
3. APIM rewrites URL to `/apim/v1.0/invoke/catalog-service/method/products` and sends to nginx-ingress FQDN
4. nginx-ingress `rewrite-target` strips `/apim` prefix → `/v1.0/invoke/catalog-service/method/products`
5. Request hits `api-gateway-dapr` service → Dapr sidecar invokes `catalog-service` via mTLS

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
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set apim_publisher_email and nginx_ingress_fqdn
terraform init
terraform apply
cd ..

# 3. Deploy APIM ingress rule to AKS
./scripts/deploy-apim-ingress.sh

# 4. Test
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

## Why Cloud Gateway via nginx-ingress?

The original design used an APIM **self-hosted gateway** running as a pod in AKS with its own Dapr sidecar (routing via `localhost:3500`). This would have been the simplest approach — the gateway pod talks directly to Dapr just like any other service.

However, the **APIM Developer SKU limits gateways to 1**, and the built-in managed (cloud) gateway counts as that one. Creating a self-hosted gateway resource fails with `"maximum number of Gateways (1)"`. The Standard/Premium SKUs allow additional gateways but cost significantly more (~$700+/month vs ~$50/month).

The solution: use the **cloud gateway** (which already exists) and route it through nginx-ingress in AKS. nginx-ingress already has a Dapr sidecar from Phase 6-8, so Dapr service invocation, mTLS, and access control all work without changes. APIM's policy features (caching, rate limiting, subscriptions, validation) are fully preserved since they execute in the cloud gateway before the request reaches AKS.

**What we keep:** All APIM policy features + all Dapr features (mTLS, service discovery, access control).

**What we lose vs. self-hosted:** The self-hosted gateway would process policies inside the cluster (lower latency, works offline). The cloud gateway adds a network hop through Azure (~10-50ms) but is simpler to operate (no gateway pods to manage).

> This is also a viable production pattern for small-to-medium APIs where the extra latency is negligible. For high-throughput or latency-sensitive workloads, upgrade to the Standard/Premium SKU to use a self-hosted gateway. See ARCHITECTURE.md for a detailed comparison.

## How Dapr Integration Works

APIM's cloud gateway has no Dapr sidecar (it runs in Azure, not in AKS). Instead, APIM routes through nginx-ingress, which already has a Dapr sidecar:

```xml
<!-- APIM policy: route to nginx-ingress backend -->
<set-backend-service backend-id="nginx-ingress-backend" />

<!-- Rewrite URL so Dapr receives standard service invocation path -->
<rewrite-uri template="/apim/v1.0/invoke/catalog-service/method/products" />
```

nginx-ingress has an ingress rule that strips the `/apim` prefix:

```yaml
# Ingress: /apim(/v1\.0/.*) → rewrite-target: $1
# Result: Dapr receives /v1.0/invoke/catalog-service/method/products
```

The Dapr sidecar on nginx-ingress (app-id: `api-gateway`) then uses service invocation with mTLS to reach the target service.

## Files

```
kubernetes-phase9-apim/
├── README.md
├── ARCHITECTURE.md
├── terraform/
│   ├── main.tf              # APIM instance (Developer SKU)
│   ├── apim.tf              # APIs, backend, policies, subscriptions
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Gateway URL, subscription key
│   ├── providers.tf         # Azure provider
│   └── terraform.tfvars.example  # Example variable values
├── scripts/
│   ├── deploy-apim-ingress.sh  # Deploy APIM ingress rule to AKS
│   ├── configure-apis.sh       # Configure APIs and policies (alternative to Terraform)
│   ├── test-apim.sh            # Test all endpoints
│   └── cleanup.sh              # Remove APIM resources
├── k8s/
│   └── apim-ingress.yaml   # Ingress for /apim/v1.0/* path (rewrite-target strips /apim)
├── policies/
│   ├── global-policy.xml    # CORS, error handling
│   ├── catalog-policy.xml   # Caching, rate limiting
│   └── orders-policy.xml    # Auth, rate limiting, validation
└── api-definitions/
    ├── catalog-api.json     # OpenAPI spec
    └── orders-api.json      # OpenAPI spec
```

## Costs

- APIM Developer SKU: ~$50/month
- No additional AKS resources (reuses existing nginx-ingress)

Remember to run `./scripts/cleanup.sh` or `terraform destroy` when not using.

## Cleanup

```bash
./scripts/cleanup.sh
# Or manually:
kubectl delete ingress dapr-demo-ingress-apim -n dapr-demo
cd terraform && terraform destroy
```
