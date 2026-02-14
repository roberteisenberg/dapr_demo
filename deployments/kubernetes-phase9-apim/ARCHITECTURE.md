# Phase 9: API Management Architecture

## Overview

Phase 9 adds Azure API Management (APIM) as an enterprise API gateway layer. The APIM cloud gateway (hosted in Azure) enforces policies, then routes through the existing nginx-ingress in AKS. nginx-ingress has a Dapr sidecar that handles service invocation to backend services via mTLS.

## Why Cloud Gateway via nginx-ingress?

The original design used an APIM **self-hosted gateway** running as a pod in AKS with its own Dapr sidecar (routing via `localhost:3500`). This would have been the simplest approach — the gateway pod talks directly to Dapr just like any other service.

However, the **APIM Developer SKU limits gateways to 1**, and the built-in managed (cloud) gateway counts as that one. Creating a self-hosted gateway resource fails with `"maximum number of Gateways (1)"`. The Standard/Premium SKUs allow additional gateways but cost significantly more (~$700+/month vs ~$50/month).

The solution: use the **cloud gateway** (which already exists) and route it through nginx-ingress in AKS. nginx-ingress already has a Dapr sidecar from Phase 6-8, so Dapr service invocation, mTLS, and access control all work without changes. APIM's policy features (caching, rate limiting, subscriptions, validation) are fully preserved since they execute in the cloud gateway before the request reaches AKS.

> **Note:** This approach was chosen to keep the demo cost-effective on the Developer SKU (~$50/month). It is also a viable production pattern for small-to-medium workloads — the extra network hop through the cloud gateway adds ~10-50ms of latency, which is negligible for most business APIs. The tradeoff:
>
> | | Cloud Gateway (this demo) | Self-Hosted Gateway (Standard/Premium SKU) |
> |---|---|---|
> | **Cost** | ~$50/month (Developer) | ~$700+/month (Standard/Premium) |
> | **Latency** | Extra hop through Azure | Policies execute inside the cluster |
> | **Offline/edge** | Requires internet connectivity | Works disconnected |
> | **Operations** | No gateway pods to manage | Must manage gateway deployment + HPA |
> | **Best for** | Small/medium APIs, cost-sensitive teams | High-throughput, latency-sensitive, or air-gapped workloads |

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                    Internet                                      │
│                                                                                  │
│          ┌─────────────────────────┐            ┌─────────────────────────┐     │
│          │ APIM Cloud Gateway      │            │ Direct Access           │     │
│          │ dapr-demo-apim          │            │ dapr-demo-xxx.eastus    │     │
│          │ .azure-api.net          │            │ .cloudapp.azure.com     │     │
│          └────────────┬────────────┘            └────────────┬────────────┘     │
│                       │                                      │                   │
│                       │  Policies applied:                   │                   │
│                       │  • Rate limiting                     │                   │
│                       │  • Caching                           │                   │
│                       │  • Subscription keys                 │                   │
│                       │  • Request validation                │                   │
│                       │                                      │                   │
│                       └──────────────┬───────────────────────┘                   │
│                                      │                                           │
│                                      ▼                                           │
└──────────────────────────────────────┼───────────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼───────────────────────────────────────────┐
│                                  AKS Cluster                                     │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                          dapr-demo namespace                               │ │
│  │                                                                            │ │
│  │  ┌───────────────────────────────────────────────────────┐                │ │
│  │  │  nginx-ingress (ingress controller)                   │                │ │
│  │  │  + Dapr sidecar (app-id: api-gateway)                 │                │ │
│  │  │                                                        │                │ │
│  │  │  Ingress rules:                                        │                │ │
│  │  │  • /v1.0/*        → api-gateway-dapr (Phase 6-8)      │                │ │
│  │  │  • /apim/v1.0/*   → api-gateway-dapr (Phase 9, APIM)  │                │ │
│  │  │  • /              → web-app (Phase 6-8)                │                │ │
│  │  └───────────────┬───────────────────────────────────────┘                │ │
│  │                  │                                                         │ │
│  │                  │ Dapr service invocation (mTLS)                          │ │
│  │                  │                                                         │ │
│  │  ┌───────────────▼───────────────────────────────────────────────────┐    │ │
│  │  │                                                                    │    │ │
│  │  │  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐  │    │ │
│  │  │  │  catalog-service  │  │  order-service    │  │ workflow-svc   │  │    │ │
│  │  │  │  + daprd          │  │  + daprd          │  │ + daprd        │  │    │ │
│  │  │  └──────────────────┘  └──────────────────┘  └────────────────┘  │    │ │
│  │  │                                                                    │    │ │
│  │  └────────────────────────────────────────────────────────────────────┘    │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │    Azure API Management       │
        │     (Management Plane)        │
        │  ┌─────────────────────────┐  │
        │  │ • API Definitions       │  │
        │  │ • Policies              │  │
        │  │ • Subscriptions         │  │
        │  │ • Analytics             │  │
        │  └─────────────────────────┘  │
        └───────────────────────────────┘
```

## Two Access Paths

Phase 9 provides two ways to reach backend services:

| Path | Entry Point | Policies | Use Case |
|------|-------------|----------|----------|
| APIM cloud gateway | `https://dapr-demo-apim.azure-api.net/api/v1/...` | Caching, rate limiting, subscriptions, validation | External API consumers |
| Direct nginx-ingress | `https://dapr-demo-xxx.cloudapp.azure.com/v1.0/...` | Phase 8 OAuth2 (if enabled) | Web app, internal use |

Both paths ultimately reach the same backend services through Dapr service invocation.

## Request Flow

### APIM Cloud Gateway Path

1. **Client** → APIM cloud gateway (`https://dapr-demo-apim.azure-api.net/api/v1/catalog`)
2. **APIM** → Applies inbound policies (rate limit, validation, cache lookup)
3. **APIM** → Rewrites URL to `/apim/v1.0/invoke/catalog-service/method/products`
4. **APIM** → Sends to nginx-ingress backend (`https://dapr-demo-xxx.cloudapp.azure.com`)
5. **nginx-ingress** → Matches `/apim(/v1\.0/.*)`, rewrites to `/v1.0/invoke/catalog-service/method/products`
6. **nginx-ingress** → Routes to `api-gateway-dapr` service
7. **Dapr sidecar** → Service invocation to `catalog-service` via mTLS
8. **Response** → Back through the chain with outbound policies (cache store, headers)

### Why the /apim Prefix?

The `/apim` prefix distinguishes APIM-routed traffic from direct nginx-ingress traffic:

- `/v1.0/*` — Direct access (Phase 6-8), may have OAuth2 protection
- `/apim/v1.0/*` — APIM-routed access (Phase 9), no OAuth2 (APIM handles auth via subscription keys)

nginx-ingress `rewrite-target` strips the `/apim` prefix so Dapr receives standard URLs.

## Components

### APIM Cloud Gateway

The cloud gateway is fully managed by Azure — no pods to deploy in AKS:

| Component | Description |
|-----------|-------------|
| Cloud Gateway | `https://dapr-demo-apim.azure-api.net` (Azure-managed) |
| Backend | Routes to nginx-ingress FQDN via HTTPS |
| Policies | Rate limiting, caching, validation, subscription keys |
| Management | Azure Portal, Terraform |

### nginx-ingress (Existing)

The existing nginx-ingress from Phase 6-8 gains one new ingress rule:

| Component | Description |
|-----------|-------------|
| Ingress Rule | `dapr-demo-ingress-apim`: `/apim/v1.0/*` → `api-gateway-dapr` |
| Dapr Sidecar | app-id: `api-gateway`, handles service invocation |
| Rewrite | Strips `/apim` prefix for Dapr |

## API Surface

### Catalog API (`/api/v1/catalog`)

Public, cached product catalog.

| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/` | GET | List products | None |
| `/{id}` | GET | Get product | None |

**Policies:**
- Rate limit: 1000 requests/minute per IP
- Response cache: 60 seconds
- Backend: `catalog-service` via Dapr

### Orders API (`/api/v1/orders`)

Order management through Dapr workflow.

| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/` | GET | List orders | API Key |
| `/` | POST | Create order | API Key |
| `/{id}` | GET | Get order status | API Key |

**Policies:**
- Rate limit: 100/min (POST), 500/min (GET)
- Request validation: JSON, max 10KB
- Backend: `workflow-service` (POST, GET/{id}), `order-service` (GET list)

## APIM Policies

### Global Policy

Applied to all APIs:

```xml
<policies>
  <inbound>
    <cors allow-credentials="true">
      <allowed-origins><origin>*</origin></allowed-origins>
      <allowed-methods>GET, POST, PUT, DELETE, OPTIONS</allowed-methods>
    </cors>
  </inbound>
  <outbound>
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
  </outbound>
</policies>
```

### Backend Routing

Routes through nginx-ingress instead of localhost (no Dapr sidecar on cloud gateway):

```xml
<!-- Route to nginx-ingress backend in AKS -->
<set-backend-service backend-id="nginx-ingress-backend" />

<!-- Rewrite URL with /apim prefix (stripped by nginx rewrite-target) -->
<rewrite-uri template="/apim/v1.0/invoke/catalog-service/method/products" />
```

### Rate Limiting

Per-key rate limiting with fallback to IP:

```xml
<rate-limit-by-key
    calls="100"
    renewal-period="60"
    counter-key="@(context.Subscription?.Key ?? context.Request.IpAddress)" />
```

### Caching

Response caching for read-heavy endpoints:

```xml
<inbound>
  <cache-lookup vary-by-developer="false" caching-type="internal">
    <vary-by-header>Accept</vary-by-header>
  </cache-lookup>
</inbound>
<outbound>
  <cache-store duration="60" />
</outbound>
```

### Request Validation

JSON validation with size limits:

```xml
<validate-content
    unspecified-content-type-action="prevent"
    max-size="10240"
    size-exceeded-action="prevent">
  <content type="application/json" validate-as="json" action="prevent" />
</validate-content>
```

## Authentication

### Subscription Keys

Orders API requires `X-API-Key` header:

```bash
# With subscription key
curl -H "X-API-Key: YOUR_KEY" https://dapr-demo-apim.azure-api.net/api/v1/orders

# Without key → 401 Unauthorized
curl https://dapr-demo-apim.azure-api.net/api/v1/orders
```

### Integration with Phase 8 Security

When combined with Phase 8:
- **APIM path**: Subscription key authentication (managed by APIM)
- **Direct path**: Azure AD JWT validation (managed by OAuth2 Proxy)
- **Internal services**: Dapr mTLS + access control policies (managed by Dapr)

## Terraform Resources

| Resource | Purpose |
|----------|---------|
| `azurerm_api_management` | APIM instance (Developer tier) |
| `azurerm_api_management_api` | API definitions (catalog, orders) |
| `azurerm_api_management_backend` | nginx-ingress backend with TLS |
| `azurerm_api_management_api_policy` | Per-API policies |
| `azurerm_api_management_product` | Product grouping for subscriptions |
| `azurerm_api_management_subscription` | API key subscription |

## Troubleshooting

### APIM Returns 502 Bad Gateway

APIM can reach nginx-ingress but backend service is unavailable:

```bash
# Check backend services
kubectl get pods -n dapr-demo

# Check Dapr sidecar on nginx-ingress
kubectl logs -n dapr-demo -l app.kubernetes.io/name=ingress-nginx -c daprd

# Test nginx-ingress directly (bypassing APIM)
curl -k https://dapr-demo-xxx.cloudapp.azure.com/apim/v1.0/invoke/catalog-service/method/products
```

### APIM Returns 500 or Timeout

APIM cannot reach nginx-ingress:

```bash
# Verify nginx-ingress is accessible
curl -k https://dapr-demo-xxx.cloudapp.azure.com/

# Check APIM backend configuration
cd terraform && terraform output nginx_ingress_fqdn

# Verify APIM ingress rule exists
kubectl get ingress dapr-demo-ingress-apim -n dapr-demo
```

### Rate Limiting Not Working

Rate limiting is handled by APIM cloud gateway (not in AKS):

```bash
# Verify policy is applied (check in Azure Portal or via API)
az apim api policy show --api-id catalog-api --resource-group rg-dapr-demo --service-name dapr-demo-apim

# Test with rapid requests
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" https://dapr-demo-apim.azure-api.net/api/v1/catalog; done
```

### Phase 8 Web App Broken After Phase 9

Phase 9 should not affect Phase 8. The new ingress rule (`/apim/v1.0/*`) is separate from existing rules:

```bash
# Verify all ingress rules
kubectl get ingress -n dapr-demo

# Should show:
# dapr-demo-ingress-api   (Phase 8: /v1.0/*)
# dapr-demo-ingress-web   (Phase 8: /)
# dapr-demo-ingress-apim  (Phase 9: /apim/v1.0/*)
```

## Implementation Notes

Lessons learned while implementing the cloud gateway approach with the Developer SKU.

### Terraform: Backend TLS Block Causes 400

The `azurerm_api_management_backend` resource with a `tls { validate_certificate_chain = false }` block returns a 400 ValidationError on the Developer SKU. Since Let's Encrypt certificates are trusted by Azure's default CA store, the `tls` block is unnecessary — remove it entirely. Only add it if using self-signed certificates on a higher SKU.

### Terraform: Policy Race Condition

API policies that reference `backend-id="nginx-ingress-backend"` fail if the backend hasn't been created yet. Terraform creates independent resources in parallel, so the policy and backend may be created simultaneously. Fix: add `depends_on = [azurerm_api_management_backend.nginx_ingress]` to both `azurerm_api_management_api_policy` resources.

### APIM Policy: `context.Request.Url.Path` Is Null After `set-backend-service`

In APIM policies, `context.Request.Url.Path` becomes null after `<set-backend-service backend-id="..." />` changes the backend. Any `<rewrite-uri>` expression that references the request path must use `context.Request.OriginalUrl.Path` instead, which preserves the original request URL regardless of backend changes. This manifests as a 500 Internal Server Error with "Object reference not set to an instance of an object" in the APIM trace.

To debug: enable tracing with `Ocp-Apim-Trace: true` header (requires subscription key), then fetch the trace URL from the `Ocp-Apim-Trace-Location` response header.
