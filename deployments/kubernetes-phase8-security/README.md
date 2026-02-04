# Phase 8: End-to-End Security on AKS

End-to-end security layered onto the AKS deployment: Azure AD login in the React app, JWT validation at the ingress, TLS via Let's Encrypt, and Dapr access control policies between services.

> **Note**: These instructions use bash (Linux/macOS/WSL2). Run them from a Linux terminal.

**Teaching Point:** "Every layer is secured: user → HTTPS → ingress (JWT) → sidecar mesh (mTLS) → service (access policies). No anonymous requests reach your backend."

## Prerequisites

- Azure CLI: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
- Terraform: [Install guide](https://developer.hashicorp.com/terraform/install)
- kubectl: `az aks install-cli`
- Helm: [Install guide](https://helm.sh/docs/intro/install/)
- Dapr CLI: [Install guide](https://docs.dapr.io/getting-started/install-dapr-cli/)
- jq: `sudo apt-get install -y jq`
- Docker Desktop (running, WSL2 backend)
- Azure subscription with permissions to create AKS clusters and register Azure AD apps

### Docker Images

Service images are published to Docker Hub at `reisenberg100/dapr-*` and are **publicly accessible** — no Docker Hub account or login required. To use your own registry, update the image references in `manifests/04-07` and `manifests/08-web-app.yaml`, then push with `./scripts/build-and-push.sh`.

## Quick Start

```bash
cd deployments/kubernetes-phase8-security

# 1. Provision AKS cluster, install cert-manager + Dapr, register Azure AD app
cd terraform
terraform init && terraform apply
cd ..
./scripts/setup-cluster.sh

# 2. Deploy with security enabled
#    (Azure AD client/tenant IDs are read from .azure-config automatically)
./scripts/deploy-all.sh --with-security

# 3. Open the HTTPS URL printed at the end and sign in with Azure AD

# 4. Test security
./scripts/test-security.sh
```

## Deploy Without Security

To deploy the same services without security (Phase 7 AI features on AKS, no auth):

```bash
./scripts/deploy-all.sh --with-frontend
```

## What's Secured

### Layer 1: TLS (Let's Encrypt)

HTTPS is required because MSAL.js uses `window.crypto.subtle`, which browsers only expose in secure contexts (HTTPS or localhost).

- **cert-manager** is installed by `setup-cluster.sh` and provisions a Let's Encrypt certificate automatically
- Both ingress resources share a single TLS certificate (`dapr-demo-tls` secret)
- HTTP requests are redirected to HTTPS

### Layer 2: React App (MSAL.js)

The React frontend uses `@azure/msal-react` for Azure AD login:
- Sign In / Sign Out button in the header
- Unauthenticated users see "Sign in to continue"
- Every API call includes `Authorization: Bearer {access_token}` via an axios interceptor
- Authorization Code flow with PKCE (no client secret needed for SPA)

**Runtime config:** Azure AD client/tenant IDs are injected via a Kubernetes ConfigMap mounted into the nginx container at `/config.js`. No Docker image rebuild needed per environment. If `AZURE_CLIENT_ID` is empty, auth is disabled and the app works without login (backward compatible with Phases 3-7).

### Layer 3: Ingress (OAuth2 Proxy)

[OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) validates JWT tokens on all API routes:
- `GET/POST /v1.0/*` → requires valid Azure AD JWT (401 if missing/invalid)
- `GET /` → public (React SPA must load to show login button)

The ingress is split into two Ingress resources:
- `dapr-demo-ingress-api` — protected, with `auth-url` annotation pointing to OAuth2 Proxy
- `dapr-demo-ingress-web` — public, serves the React SPA

**Note:** Azure AD issues access tokens with issuer `https://sts.windows.net/{tenant}/` (v1.0 format) even when using the v2.0 endpoint. OAuth2 Proxy is configured to accept both issuers via `--extra-jwt-issuers`.

### Layer 4: Dapr mTLS

Dapr Sentry automatically provides mutual TLS between all sidecars. Already running since Phase 3. Verify with:

```bash
dapr mtls -k
```

### Layer 5: Dapr Access Control

The Dapr Configuration restricts which services can call which endpoints:

| Caller | Can Call | Endpoints |
|--------|---------|-----------|
| api-gateway | catalog-service | `/products/*` |
| api-gateway | order-service | `/orders/*` |
| api-gateway | workflow-service | `/workflows/*` |
| workflow-service | catalog-service | `/products/*` |
| workflow-service | order-service | `/orders/*` |
| Everything else | — | **DENIED** |

This means a compromised service can't call arbitrary endpoints on other services.

## Request Flow (Secured)

```
User → Browser (HTTPS)
       │
       ├─ Not signed in? Show "Sign In" button
       │   └─ Click → Azure AD login (PKCE) → redirect back with tokens
       │
       ├─ Signed in? Show app with user name + "Sign Out"
       │   └─ Every API call: Authorization: Bearer {access_token}
       │
       ▼
NGINX Ingress (TLS termination, Let's Encrypt cert)
       │
       ├─ /v1.0/* → OAuth2 Proxy validates JWT
       │   ├─ Invalid/missing token → 401 Unauthorized
       │   └─ Valid token → forward to Dapr sidecar
       │
       ├─ /* → Serve React static files (no auth required)
       │
       ▼
Dapr sidecar (api-gateway)
       │
       ├─ Access control: can this app-id call this endpoint?
       │   ├─ Denied → 403
       │   └─ Allowed → forward via mTLS
       │
       ▼
Target service sidecar (mTLS encrypted)
       │
       ▼
Service container
```

## Azure AD App Registration

The `setup-cluster.sh` script automatically registers an Azure AD (Entra ID) app called `dapr-demo-frontend` using the Microsoft Graph API. It:

1. Creates a single-tenant SPA app registration
2. Sets redirect URIs to the AKS HTTPS URL, `http://localhost:3000/`, and `http://localhost:8080/`
3. Configures an API scope (`access_as_user`)
4. Saves the **Client ID** and **Tenant ID** to `.azure-config`

No client secret needed — this is a public SPA client using Authorization Code with PKCE.

The `deploy-all.sh --with-security` script reads these values automatically.

### Manual Registration (if automation fails)

If your Azure account lacks permissions to register apps (requires Application Administrator or similar role), register manually:

1. Azure Portal → Entra ID → App registrations → New registration
2. Name: `dapr-demo-frontend`
3. Redirect URI (SPA): your AKS HTTPS URL (output by `setup-cluster.sh`), `http://localhost:3000/`, and `http://localhost:8080/`
4. Supported account types: Single tenant
5. Expose an API → Add scope: `access_as_user`
6. Note the **Application (client) ID** and **Directory (tenant) ID**

Then deploy with:

```bash
./scripts/deploy-all.sh --with-security \
  --azure-client-id "YOUR_CLIENT_ID" \
  --azure-tenant-id "YOUR_TENANT_ID"
```

## Files

### New (Security)
| File | Purpose |
|------|---------|
| `manifests/11-oauth2-proxy.yaml` | OAuth2 Proxy deployment + service |
| `manifests/09-ingress.yaml` | Split TLS ingress (API protected, web public) |
| `manifests/09-ingress-nosecurity.yaml` | Original single ingress (no auth, HTTP) |
| `scripts/test-security.sh` | Security verification tests |

### Modified (from Phase 6/7)
| File | Change |
|------|--------|
| `manifests/08-web-app.yaml` | ConfigMap volume mount for runtime Azure AD config |
| `manifests/03-components/tracing.yaml` | Added Dapr access control policies |
| `scripts/setup-cluster.sh` | Added cert-manager install and Azure AD app registration |
| `scripts/deploy-all.sh` | Added `--with-security`, TLS ingress with FQDN substitution |

### React App (shared `frontend/web-app/`)
| File | Change |
|------|--------|
| `src/authConfig.js` | MSAL configuration (reads `window.__CONFIG__` at runtime) |
| `src/components/SignInButton.js` | Sign In/Out button |
| `public/config.js` | Runtime config defaults (overridden by ConfigMap in K8s) |
| `src/index.js` | MSAL initialization, conditional MsalProvider wrapper |
| `src/App.js` | AuthGate component, user display in header |
| `src/services/api.js` | Bearer token interceptor via `acquireTokenSilent` |
| `package.json` | Added `@azure/msal-browser`, `@azure/msal-react` |

## Troubleshooting

### MSAL blank page
MSAL.js requires `window.crypto.subtle`, which is only available over HTTPS (or localhost). If the page is blank, check:
- The site is accessed via `https://` (not `http://`)
- cert-manager issued the TLS certificate: `kubectl get certificate -n dapr-demo`
- No errors in browser console (F12)

### OAuth2 Proxy 401 despite valid token
Check OAuth2 Proxy logs for the rejection reason:
```bash
kubectl logs deployment/oauth2-proxy -n dapr-demo --tail=20
```
Common issues:
- **Issuer mismatch**: Azure AD access tokens use `sts.windows.net` (v1.0) issuer even from v2.0 endpoint. Both issuers must be in `--extra-jwt-issuers`.
- **Audience mismatch**: Tokens with `api://` scopes have `aud: api://{clientId}`, not just `{clientId}`.
- **Trailing whitespace**: Check ConfigMap values with `kubectl get configmap oauth2-proxy-config -n dapr-demo -o yaml`.

### ingress-nginx blocks auth annotations
If OAuth2 Proxy auth annotations are rejected as "risky", set `annotations-risk-level: "Critical"` in `config/ingress-values.yaml` and upgrade the Helm release.

## What We're NOT Doing

- **Key Vault** — K8s secrets are fine for this demo. Key Vault adds complexity without a clear teaching payoff.
- **Network Policies** — K8s-level network segmentation. Good practice but orthogonal to the Dapr security story.
- **Pod Security Standards** — Important for production, not for this demo's scope.

## Cleanup

```bash
./scripts/cleanup.sh
```
