#!/bin/bash
# Deploy all services to AKS (Phase 8 - Security)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

# Load Azure configuration
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Azure configuration not found."
    echo "Run ./scripts/setup-cluster.sh first."
    exit 1
fi

# Defaults (preserve AZURE_CLIENT_ID/TENANT_ID if already loaded from .azure-config)
WITH_FRONTEND=false
WITH_SECURITY=false
PUBSUB_BACKEND="redis"
STATESTORE_BACKEND="redis"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-frontend)
            WITH_FRONTEND=true
            shift
            ;;
        --with-security)
            WITH_SECURITY=true
            WITH_FRONTEND=true  # Security requires frontend
            shift
            ;;
        --azure-client-id)
            AZURE_CLIENT_ID="$2"
            shift 2
            ;;
        --azure-tenant-id)
            AZURE_TENANT_ID="$2"
            shift 2
            ;;
        --pubsub)
            PUBSUB_BACKEND="$2"
            shift 2
            ;;
        --statestore)
            STATESTORE_BACKEND="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--with-frontend] [--with-security] [--azure-client-id ID] [--azure-tenant-id ID] [--pubsub redis|rabbitmq] [--statestore redis|mongodb]"
            exit 1
            ;;
    esac
done

# Validate options
if [[ "$PUBSUB_BACKEND" != "redis" && "$PUBSUB_BACKEND" != "rabbitmq" ]]; then
    echo "Error: Invalid pub/sub backend '$PUBSUB_BACKEND'. Must be 'redis' or 'rabbitmq'."
    exit 1
fi

if [[ "$STATESTORE_BACKEND" != "redis" && "$STATESTORE_BACKEND" != "mongodb" ]]; then
    echo "Error: Invalid state store backend '$STATESTORE_BACKEND'. Must be 'redis' or 'mongodb'."
    exit 1
fi

# Validate security options
if [[ "$WITH_SECURITY" == "true" ]]; then
    # Auto-read from .azure-config if not provided via CLI
    if [[ -z "$AZURE_CLIENT_ID" ]] && [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    if [[ -z "$AZURE_TENANT_ID" ]] && [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    if [[ -z "$AZURE_CLIENT_ID" || -z "$AZURE_TENANT_ID" ]]; then
        echo "Error: --with-security requires Azure AD client and tenant IDs."
        echo ""
        echo "These are normally set automatically by setup-cluster.sh."
        echo "To provide manually:"
        echo "  $0 --with-security --azure-client-id <CLIENT_ID> --azure-tenant-id <TENANT_ID>"
        echo ""
        echo "Or re-run ./scripts/setup-cluster.sh to register the Azure AD app."
        exit 1
    fi
fi

echo "========================================="
echo "Deploying to Azure Kubernetes Service"
echo "========================================="
echo "Registry:    Docker Hub (reisenberg100/dapr-*)"
echo "Pub/Sub:     $PUBSUB_BACKEND"
echo "State Store: $STATESTORE_BACKEND"
echo "Frontend:    $WITH_FRONTEND"
echo "Security:    $WITH_SECURITY"
if [[ "$WITH_SECURITY" == "true" ]]; then
echo "  Client ID: $AZURE_CLIENT_ID"
echo "  Tenant ID: $AZURE_TENANT_ID"
fi
echo ""

# Function to apply manifest
apply_manifest() {
    local file="$1"
    if [ -f "$file" ]; then
        kubectl apply -f "$file"
    fi
}

# Deploy namespace
echo "Creating namespace..."
kubectl apply -f "$MANIFESTS_DIR/00-namespace.yaml"

# Deploy infrastructure
echo "Deploying Redis..."
kubectl apply -f "$MANIFESTS_DIR/01-redis.yaml"

echo "Deploying Zipkin..."
kubectl apply -f "$MANIFESTS_DIR/10-zipkin.yaml"

if [[ "$PUBSUB_BACKEND" == "rabbitmq" ]]; then
    echo "Deploying RabbitMQ..."
    kubectl apply -f "$MANIFESTS_DIR/02-rabbitmq.yaml"
fi

if [[ "$STATESTORE_BACKEND" == "mongodb" ]]; then
    echo "Deploying MongoDB..."
    kubectl apply -f "$MANIFESTS_DIR/02-mongodb.yaml"
fi

# Copy component templates
echo "Configuring Dapr components..."
cp "$MANIFESTS_DIR/03-components/templates/pubsub-$PUBSUB_BACKEND.yaml" "$MANIFESTS_DIR/03-components/pubsub.yaml"
cp "$MANIFESTS_DIR/03-components/templates/statestore-$STATESTORE_BACKEND.yaml" "$MANIFESTS_DIR/03-components/statestore.yaml"

# Deploy components
kubectl apply -f "$MANIFESTS_DIR/03-components/"

# Wait for infrastructure
echo "Waiting for infrastructure..."
kubectl wait --for=condition=available --timeout=300s deployment/redis -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/zipkin -n dapr-demo

if [[ "$PUBSUB_BACKEND" == "rabbitmq" ]]; then
    kubectl wait --for=condition=available --timeout=300s deployment/rabbitmq -n dapr-demo
fi

if [[ "$STATESTORE_BACKEND" == "mongodb" ]]; then
    kubectl wait --for=condition=available --timeout=300s deployment/mongodb -n dapr-demo
fi

# Check for API key secret (required for fraud check via Dapr Conversation API)
if ! kubectl get secret anthropic-api-key -n dapr-demo &>/dev/null; then
    echo ""
    echo "WARNING: Kubernetes secret 'anthropic-api-key' not found in dapr-demo namespace."
    echo "The fraud check in the order workflow requires a Claude API key."
    echo ""
    echo "Create it with:"
    echo "  kubectl create secret generic anthropic-api-key --from-literal=api-key=\$ANTHROPIC_API_KEY -n dapr-demo"
    echo ""
    echo "Continuing deployment — fraud check will approve all orders by default."
    echo ""
fi

# Deploy services
echo "Deploying services..."
apply_manifest "$MANIFESTS_DIR/04-catalog-service.yaml"
apply_manifest "$MANIFESTS_DIR/05-order-service.yaml"
apply_manifest "$MANIFESTS_DIR/06-notification-service.yaml"
apply_manifest "$MANIFESTS_DIR/07-workflow-service.yaml"

# Deploy frontend (optional, or required with security)
if [[ "$WITH_FRONTEND" == "true" ]]; then
    # Create web-app ConfigMap with Azure AD values (or empty defaults)
    if [[ "$WITH_SECURITY" == "true" ]]; then
        echo "Configuring web-app with Azure AD..."
        CONFIG_JS_FILE="/tmp/dapr-demo-config.js"
        printf 'window.__CONFIG__ = {\n  AZURE_CLIENT_ID: "%s",\n  AZURE_TENANT_ID: "%s"\n};\n' "$AZURE_CLIENT_ID" "$AZURE_TENANT_ID" > "$CONFIG_JS_FILE"
    else
        CONFIG_JS_FILE="/tmp/dapr-demo-config.js"
        printf 'window.__CONFIG__ = {\n  AZURE_CLIENT_ID: "",\n  AZURE_TENANT_ID: ""\n};\n' > "$CONFIG_JS_FILE"
    fi
    kubectl create configmap web-app-config \
        --from-file="config.js=${CONFIG_JS_FILE}" \
        --namespace dapr-demo \
        --dry-run=client -o yaml | kubectl apply -f -
    rm -f "$CONFIG_JS_FILE"

    echo "Deploying web-app..."
    apply_manifest "$MANIFESTS_DIR/08-web-app.yaml"
fi

# Deploy security components (if enabled)
if [[ "$WITH_SECURITY" == "true" ]]; then
    echo ""
    echo "Deploying security components..."

    # Generate cookie secret for OAuth2 Proxy
    COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())' 2>/dev/null || \
                    openssl rand -base64 32 2>/dev/null || \
                    echo "fallback-cookie-secret-change-me")

    # Deploy OAuth2 Proxy secret with generated cookie secret
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secret
  namespace: dapr-demo
type: Opaque
stringData:
  cookie-secret: "${COOKIE_SECRET}"
EOF

    # Deploy OAuth2 Proxy config with Azure AD values
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-config
  namespace: dapr-demo
data:
  AZURE_CLIENT_ID: "${AZURE_CLIENT_ID}"
  AZURE_TENANT_ID: "${AZURE_TENANT_ID}"
EOF

    echo "Deploying OAuth2 Proxy..."
    apply_manifest "$MANIFESTS_DIR/11-oauth2-proxy.yaml"

    echo "Deploying secured ingress (API routes require JWT)..."
    FQDN="$DNS_LABEL.$LOCATION.cloudapp.azure.com"
    sed "s/FQDN_PLACEHOLDER/$FQDN/g" "$MANIFESTS_DIR/09-ingress.yaml" | kubectl apply -f -

    # Wait for OAuth2 Proxy
    kubectl wait --for=condition=available --timeout=300s deployment/oauth2-proxy -n dapr-demo
else
    # Deploy standard ingress (no auth)
    echo "Deploying ingress (no security)..."
    kubectl apply -f "$MANIFESTS_DIR/09-ingress-nosecurity.yaml"
fi

# Wait for services
echo "Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/catalog-service -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/order-service -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/notification-service -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/workflow-service -n dapr-demo

if [[ "$WITH_FRONTEND" == "true" ]]; then
    kubectl wait --for=condition=available --timeout=300s deployment/web-app -n dapr-demo
fi

# Get public URL (HTTPS when security is enabled — MSAL requires crypto.subtle)
if [[ "$WITH_SECURITY" == "true" ]]; then
    PUBLIC_URL="https://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
else
    PUBLIC_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
fi

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Pub/Sub:     $PUBSUB_BACKEND"
echo "  State Store: $STATESTORE_BACKEND"
echo "  Frontend:    $WITH_FRONTEND"
echo "  Security:    $WITH_SECURITY"
echo ""
echo "Public access (no port-forward needed!):"
echo "  URL: $PUBLIC_URL"
echo ""
echo "Test:"
echo "  API:     curl $PUBLIC_URL/v1.0/invoke/catalog-service/method/products"
if [[ "$WITH_FRONTEND" == "true" ]]; then
echo "  Web App: $PUBLIC_URL/"
fi
echo ""
echo "  ./scripts/test-services.sh      # Basic service tests"
echo "  ./scripts/test-workflow.sh      # Saga pattern workflow tests"
if [[ "$WITH_SECURITY" == "true" ]]; then
echo "  ./scripts/test-security.sh      # Security tests (JWT, access control)"
echo ""
echo "Security:"
echo "  API requests to /v1.0/* require a valid Azure AD JWT token."
echo "  The React app handles login/logout via MSAL.js."
echo "  Dapr access control restricts inter-service calls."
echo "  Verify mTLS: dapr mtls -k"
fi
echo ""
echo "Dashboards (use port-forward for internal services):"
echo "  Zipkin:   kubectl port-forward -n dapr-demo svc/zipkin 9411:9411"
echo "            http://localhost:9411"
echo "  Dapr:     dapr dashboard -k -n dapr-demo"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -n dapr-demo"
echo "  kubectl logs -f deployment/notification-service -c notification-service -n dapr-demo"
echo "========================================="
