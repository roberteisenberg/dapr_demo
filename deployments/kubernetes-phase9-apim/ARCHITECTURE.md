# Phase 9: API Management Architecture

## Overview

Phase 9 adds Azure API Management (APIM) as an enterprise API gateway layer. The APIM self-hosted gateway runs inside AKS with a Dapr sidecar, routing requests to backend services through Dapr service invocation.

**Key architecture change:** APIM gets its own Azure Load Balancer (not going through nginx-ingress). This provides a dedicated public IP for API traffic.

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                      Internet                                          │
│                                                                                        │
│            ┌────────────────────────┐              ┌────────────────────────┐         │
│            │ dapr-demo-api.eastus   │              │ dapr-demo.eastus       │         │
│            │ .cloudapp.azure.com    │              │ .cloudapp.azure.com    │         │
│            └───────────┬────────────┘              └───────────┬────────────┘         │
│                        │                                       │                       │
│                        ▼                                       ▼                       │
│            ┌────────────────────────┐              ┌────────────────────────┐         │
│            │  Azure Load Balancer   │              │  Azure Load Balancer   │         │
│            │  (APIM Gateway LB)     │              │  (nginx-ingress LB)    │         │
│            └───────────┬────────────┘              └───────────┬────────────┘         │
│                        │                                       │                       │
└────────────────────────┼───────────────────────────────────────┼───────────────────────┘
                         │                                       │
┌────────────────────────▼───────────────────────────────────────▼───────────────────────┐
│                                    AKS Cluster                                          │
│                                                                                         │
│  ┌──────────────────────────────────┐        ┌──────────────────────────────────┐     │
│  │       apim-gateway namespace      │        │       dapr-demo namespace         │     │
│  │                                   │        │                                   │     │
│  │  ┌─────────────────────────────┐ │        │  ┌──────────────┐                 │     │
│  │  │  APIM Self-Hosted Gateway   │ │        │  │  web-app     │ (React SPA)     │     │
│  │  │  service: LoadBalancer      │ │        │  └──────────────┘                 │     │
│  │  │  + Dapr sidecar             │ │        │                                   │     │
│  │  │    (app-id: apim-gateway)   │ │        │  ┌──────────────┐                 │     │
│  │  └─────────────┬───────────────┘ │        │  │ nginx-ingress│ (for web-app)   │     │
│  │                │                  │        │  │ + Dapr sidecar│                │     │
│  │                │ localhost:3500   │        │  └──────────────┘                 │     │
│  │                │                  │        │                                   │     │
│  └────────────────┼──────────────────┘        │  ┌──────────────┐ ┌────────────┐ │     │
│                   │                           │  │catalog-service│ │order-svc  │ │     │
│                   └───────────────────────────┼─►│  + daprd      │ │ + daprd   │ │     │
│                                               │  └──────────────┘ └────────────┘ │     │
│                                               │                                   │     │
│                                               │  ┌──────────────┐ ┌────────────┐ │     │
│                                               │  │workflow-svc  │ │notification│ │     │
│                                               │  │  + daprd     │ │ + daprd    │ │     │
│                                               │  └──────────────┘ └────────────┘ │     │
│                                               └───────────────────────────────────┘     │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
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

## Two Public Endpoints

Phase 9 provides two separate public endpoints:

| Endpoint | Load Balancer | Purpose |
|----------|---------------|---------|
| `http://dapr-demo-api.{region}.cloudapp.azure.com/api/v1/...` | APIM Gateway LB | API traffic with policies |
| `http://dapr-demo.{region}.cloudapp.azure.com/` | nginx-ingress LB | Web app (React SPA) |

## Components

### APIM Self-Hosted Gateway

The self-hosted gateway runs as a container in AKS, connecting to Azure APIM for configuration:

| Component | Description |
|-----------|-------------|
| Gateway Pod | `mcr.microsoft.com/azure-api-management/gateway:2.5.0` |
| Dapr Sidecar | Handles service invocation to backend services |
| Config Sync | Pulls API definitions and policies from Azure APIM |
| HPA | Auto-scales from 2-10 replicas based on CPU/memory |

### Request Flow

1. **Client** → Azure Load Balancer (APIM public IP)
2. **Azure LB** → APIM Gateway pod (port 8080)
3. **Gateway** → Applies inbound policies (rate limit, validation, caching)
4. **Gateway** → Dapr sidecar (`localhost:3500/v1.0/invoke/{service}/method/{endpoint}`)
5. **Dapr** → Backend service via service invocation (mTLS)
6. **Response** → Back through the chain with outbound policies

**No nginx-ingress in the API path.** APIM has its own LoadBalancer service that gets a public IP directly from Azure.

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
- Backend: `workflow-service` (POST), `order-service` (GET list)

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

### Backend Routing via Dapr

Routes to Dapr sidecar for service invocation:

```xml
<set-backend-service
    base-url="http://localhost:3500/v1.0/invoke/catalog-service/method" />
<rewrite-uri template="/products" />
```

## Authentication

### Subscription Keys

Orders API requires `X-API-Key` header:

```bash
# With subscription key
curl -H "X-API-Key: YOUR_KEY" https://gateway/api/v1/orders

# Without key → 401 Unauthorized
curl https://gateway/api/v1/orders
```

### Integration with Phase 8 Security

When combined with Phase 8:
- **External access**: APIM subscription key + optional Azure AD JWT
- **Internal services**: Dapr mTLS + access control policies
- **Web app**: Azure AD login → JWT → APIM validates → Dapr routes

## Terraform Resources

| Resource | Purpose |
|----------|---------|
| `azurerm_api_management` | APIM instance (Developer tier) |
| `azurerm_api_management_gateway` | Self-hosted gateway definition |
| `azurerm_api_management_api` | API definitions (catalog, orders) |
| `azurerm_api_management_api_policy` | Per-API policies |
| `azurerm_api_management_product` | Product grouping |
| `azurerm_api_management_subscription` | API key subscription |

## Monitoring

### Metrics Available

- Request count by API/operation
- Response latency percentiles
- Error rates by status code
- Cache hit ratio
- Rate limit hits

### Logs

Gateway logs include:
- Request/response details
- Policy execution results
- Backend errors
- Dapr sidecar communication

Access via:
```bash
kubectl logs -n apim-gateway -l app=apim-gateway -c apim-gateway
kubectl logs -n apim-gateway -l app=apim-gateway -c daprd
```

## Scaling

### Horizontal Pod Autoscaler

```yaml
minReplicas: 2
maxReplicas: 10
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70
```

### Production Recommendations

1. **APIM Tier**: Use Standard or Premium for production (Developer is for testing)
2. **Rate Limit Storage**: Use Redis for distributed rate limiting
3. **Gateway Replicas**: Minimum 3 across availability zones
4. **Caching**: Enable Azure Redis Cache for APIM
5. **Monitoring**: Connect to Azure Monitor and Application Insights

## Troubleshooting

### Gateway Not Starting

```bash
# Check pod status
kubectl get pods -n apim-gateway

# Check gateway logs
kubectl logs -n apim-gateway -l app=apim-gateway -c apim-gateway

# Verify config endpoint
kubectl get configmap apim-gateway-env -n apim-gateway -o yaml
```

### 502 Bad Gateway

Usually indicates backend service unavailable:

```bash
# Check Dapr sidecar logs
kubectl logs -n apim-gateway -l app=apim-gateway -c daprd

# Verify backend service is running
kubectl get pods -n dapr-demo
```

### Rate Limiting Not Working

```bash
# Check policy is applied
az apim api policy show --api-id catalog-api ...

# Gateway may need restart to pull new config
kubectl rollout restart deployment/apim-gateway -n apim-gateway
```
