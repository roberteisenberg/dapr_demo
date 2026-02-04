# Phase 8: Security Architecture

This document explains the security layers added in Phase 8, building on the Phase 6 AKS infrastructure and Phase 7 AI features.

## Security Layers

Phase 8 adds five layers of security, each independent and composable:

```
┌────────────────────────────────────────────────────────────────────┐
│                         Internet                                   │
│                            │                                       │
│                   ┌────────▼────────┐                              │
│                   │  AKS Load      │                              │
│                   │  Balancer       │                              │
│                   └────────┬────────┘                              │
│                            │                                       │
│  ┌─────────────────────────▼──────────────────────────────────┐   │
│  │                    AKS Cluster                              │   │
│  │                                                             │   │
│  │  ┌──────────────────────────────────────────────────────┐  │   │
│  │  │  NGINX Ingress Controller (Layer 1: TLS)             │  │   │
│  │  │  (with Dapr sidecar: app-id=api-gateway)             │  │   │
│  │  │  (Let's Encrypt cert via cert-manager)               │  │   │
│  │  │                                                      │  │   │
│  │  │  /v1.0/* ─── auth-url ──▶ OAuth2 Proxy ──▶ validate  │  │   │
│  │  │              (Layer 3)    JWT from Azure AD           │  │   │
│  │  │                           401 if invalid              │  │   │
│  │  │                                                      │  │   │
│  │  │  /* ──────── no auth ──▶ web-app (React SPA)         │  │   │
│  │  │              (Layer 2)   Sign In via MSAL.js          │  │   │
│  │  └──────────────────────┬───────────────────────────────┘  │   │
│  │                         │                                   │   │
│  │                  (Layer 4: mTLS)                            │   │
│  │                         │                                   │   │
│  │  ┌──────────────────────▼───────────────────────────────┐  │   │
│  │  │  Dapr Sidecar Mesh                                   │  │   │
│  │  │  (Layer 5: Access Control)                           │  │   │
│  │  │                                                      │  │   │
│  │  │  api-gateway ──▶ catalog-service (/products/*)       │  │   │
│  │  │              ──▶ order-service (/orders/*)            │  │   │
│  │  │              ──▶ workflow-service (/workflows/*)      │  │   │
│  │  │                                                      │  │   │
│  │  │  workflow-service ──▶ catalog-service (/products/*)   │  │   │
│  │  │                  ──▶ order-service (/orders/*)        │  │   │
│  │  │                                                      │  │   │
│  │  │  All other cross-service calls: DENIED               │  │   │
│  │  └──────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

## How the Security Works

The core principle: **both the frontend and backend independently trust Azure AD as the identity provider**. Neither side handles passwords or manages user accounts directly.

1. The React app redirects the user to Azure AD to log in. Azure AD authenticates the user and issues an **access token** — a signed JWT containing user-specific claims (user ID, email, name, roles, expiry).

2. Every API call from the browser includes this token as an `Authorization: Bearer` header.

3. At the ingress, OAuth2 Proxy validates the token — checking the cryptographic signature against Azure AD's public keys, plus the issuer, audience, and expiry. If invalid or missing, the request is rejected with 401 before it reaches any backend service.

Each user gets their own unique token. The token cannot be forged because it's signed by Azure AD's private key, and OAuth2 Proxy verifies the signature using Azure AD's published public keys.

### OAuth Flow: Authorization Code with PKCE

This uses the **Authorization Code flow with PKCE** (Proof Key for Code Exchange), the recommended OAuth 2.0 flow for single-page applications:

1. React app generates a random `code_verifier` and its SHA-256 hash (`code_challenge`)
2. User is redirected to Azure AD login with the `code_challenge`
3. User authenticates, Azure AD redirects back with a short-lived **authorization code**
4. MSAL.js exchanges the code + original `code_verifier` for an **access token**
5. Azure AD verifies the `code_verifier` matches the `code_challenge` before issuing the token

**Why PKCE?** SPAs run entirely in the browser — they can't securely store a client secret. PKCE proves that the app requesting the login is the same one exchanging the authorization code for a token, without needing a secret. The `code_verifier` is generated fresh each time and never leaves the browser until the exchange.

Access tokens expire (typically 1 hour). MSAL.js silently refreshes them via `acquireTokenSilent()` so the user stays logged in without repeated redirects.

## Layer 1: TLS (Let's Encrypt + cert-manager)

MSAL.js requires `window.crypto.subtle` for PKCE token exchange, which browsers only expose in **secure contexts** (HTTPS or localhost). Without TLS, the MSAL constructor throws `BrowserAuthError: crypto_nonexistent` and authentication cannot work.

cert-manager is installed by `setup-cluster.sh` and creates a `ClusterIssuer` for Let's Encrypt. The ingress manifests include `cert-manager.io/cluster-issuer: "letsencrypt"` annotations, which trigger automatic certificate provisioning. The certificate is stored in a Kubernetes secret (`dapr-demo-tls`) shared by both ingress resources.

## Layer 2: React App Authentication (MSAL.js)

The React SPA uses `@azure/msal-react` with the authorization code flow + PKCE. No client secret is needed — the SPA is a public client.

**Key design:** Runtime configuration via `window.__CONFIG__`. The Docker image ships with empty config. In Kubernetes, a ConfigMap provides real Azure AD values, mounted over `config.js` in the nginx container. This avoids rebuilding the image per environment.

```
public/config.js (default)          K8s ConfigMap (mounted)
─────────────────────               ──────────────────────
window.__CONFIG__ = {               window.__CONFIG__ = {
  AZURE_CLIENT_ID: "",                AZURE_CLIENT_ID: "abc-123",
  AZURE_TENANT_ID: ""                AZURE_TENANT_ID: "def-456"
};                                  };
```

When `AZURE_CLIENT_ID` is empty, MSAL is not initialized and the app runs without auth (backward compatible with Phases 3-7).

## Layer 3: Ingress JWT Validation (OAuth2 Proxy)

OAuth2 Proxy runs as a separate deployment in the `dapr-demo` namespace. The NGINX ingress uses `auth-url` annotation to send subrequests to OAuth2 Proxy before forwarding to the Dapr sidecar.

```
Client Request                 NGINX Ingress
─────────────                  ────────────
GET /v1.0/invoke/...           1. Receive request
Authorization: Bearer xxx      2. Subrequest to OAuth2 Proxy /oauth2/auth
                               3a. 200 → forward to api-gateway-dapr
                               3b. 401 → return 401 to client
```

The ingress is split into two Ingress resources so that `/` (React SPA) is public while `/v1.0/*` (API) requires authentication.

## Layer 4: Dapr mTLS

Dapr Sentry (part of the Dapr control plane installed in Phase 3) automatically provisions and rotates mTLS certificates for all sidecars. All sidecar-to-sidecar communication is encrypted.

This layer requires no configuration — it's been active since Dapr was installed. Phase 8 simply documents and verifies it.

## Layer 5: Dapr Access Control

The Dapr Configuration resource (`tracing.yaml`) includes `accessControl` policies that restrict which app-ids can invoke which endpoints. The `defaultAction: deny` means any call not explicitly listed is blocked.

This provides defense-in-depth: even if a service is compromised, it can only call the specific endpoints its policy allows. For example, `notification-service` cannot call `catalog-service` — it has no policy entry and the default is deny.

## Token Flow

```
1. User clicks "Sign In" in React app
2. MSAL.js redirects to login.microsoftonline.com
3. User authenticates with Azure AD
4. Azure AD redirects back with authorization code
5. MSAL.js exchanges code for tokens (PKCE, no secret)
6. Access token stored in sessionStorage
7. Every API call: axios interceptor calls acquireTokenSilent()
8. Token attached as Authorization: Bearer header
9. NGINX ingress forwards subrequest to OAuth2 Proxy
10. OAuth2 Proxy validates JWT signature, issuer, audience
11. If valid → request reaches Dapr sidecar
12. Dapr access control checks app-id + endpoint
13. If allowed → mTLS-encrypted call to target service
```

**Azure AD issuer note:** Access tokens issued for APIs with `api://` identifier URIs use the v1.0 issuer format (`https://sts.windows.net/{tenant}/`) even when requested via the v2.0 endpoint. OAuth2 Proxy must be configured with both issuers via `--extra-jwt-issuers` to handle this.

## Backward Compatibility

- **No Azure AD config?** → MSAL not initialized, app works without auth
- **No `--with-security` flag?** → Original ingress (no auth), no OAuth2 Proxy deployed
- **Access control** → Only in Phase 8's `tracing.yaml`, not shared with other phases
- **React source** → Shared `frontend/web-app/`, works in all phases
