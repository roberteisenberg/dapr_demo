#!/bin/bash
# Post-Terraform setup: Configure kubectl, install Dapr and nginx-ingress
# Run this after 'terraform apply' completes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

echo "========================================="
echo "Phase 8: Post-Terraform Cluster Setup"
echo "========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found."
    exit 1
fi
echo "  kubectl: OK"

if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm not found."
    exit 1
fi
echo "  Helm: OK"

if ! command -v dapr &> /dev/null; then
    echo "ERROR: Dapr CLI not found."
    exit 1
fi
echo "  Dapr CLI: OK"

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq not found. Install: sudo apt-get install -y jq"
    exit 1
fi
echo "  jq: OK"

# Load existing config or read from Terraform
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    echo "  Loading existing configuration..."
    source "$CONFIG_FILE"
else
    if ! command -v terraform &> /dev/null; then
        echo "ERROR: Terraform not found and no existing config."
        echo "  Install: https://developer.hashicorp.com/terraform/install"
        exit 1
    fi
    echo "  Terraform: OK"
    echo ""

    # Get Terraform outputs
    echo "Reading Terraform outputs..."
    cd "$TERRAFORM_DIR"

    if [ ! -f "terraform.tfstate" ]; then
        echo "ERROR: Terraform state not found. Run 'terraform apply' first."
        exit 1
    fi

    RESOURCE_GROUP=$(terraform output -raw resource_group_name)
    AKS_NAME=$(terraform output -raw aks_cluster_name)
    LOCATION=$(terraform output -raw location)
fi

echo "  Resource Group: $RESOURCE_GROUP"
echo "  AKS Cluster:    $AKS_NAME"
echo ""

# Configure kubectl
echo "Configuring kubectl for AKS..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing
echo "  kubectl configured"
echo ""

# Verify cluster connection
echo "Verifying cluster connection..."
kubectl get nodes
echo ""

# Install Dapr on AKS
echo "Installing Dapr on AKS..."
if kubectl get namespace dapr-system &> /dev/null; then
    echo "  Dapr already installed"
    dapr status -k
else
    dapr init -k --wait --timeout 600
    echo ""
    echo "Dapr installation complete:"
    dapr status -k
fi

# Create namespace
echo ""
echo "Creating dapr-demo namespace..."
kubectl create namespace dapr-demo 2>/dev/null || echo "  Namespace already exists"

# Create tracing config (required by ingress controller's Dapr sidecar)
echo "Creating Dapr tracing configuration..."
cat <<EOF | kubectl apply -f -
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: tracing
  namespace: dapr-demo
spec:
  tracing:
    samplingRate: "1"
    zipkin:
      endpointAddress: "http://zipkin.dapr-demo.svc.cluster.local:9411/api/v2/spans"
EOF

# Use existing DNS label or generate new one
if [ -z "$DNS_LABEL" ]; then
    DNS_LABEL="dapr-demo-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
fi

# Install cert-manager for TLS (MSAL.js requires HTTPS)
echo ""
echo "Installing cert-manager for TLS..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update jetstack

helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --timeout 5m

echo "  Waiting for cert-manager..."
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager

# Install nginx-ingress with Dapr sidecar
echo ""
echo "Installing nginx-ingress with Dapr sidecar..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx

helm upgrade --install api-gateway ingress-nginx/ingress-nginx \
    --namespace dapr-demo \
    --values "$SCRIPT_DIR/../config/ingress-values.yaml" \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"="$DNS_LABEL" \
    --timeout 10m

# Wait for the ingress controller
echo "  Waiting for ingress controller..."
kubectl wait --for=condition=available --timeout=300s deployment/api-gateway-ingress-nginx-controller -n dapr-demo

# Get public IP
echo ""
echo "Waiting for public IP assignment..."
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
    EXTERNAL_IP=$(kubectl get svc api-gateway-ingress-nginx-controller -n dapr-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -z "$EXTERNAL_IP" ]; then
        echo "  Waiting for external IP..."
        sleep 10
    fi
done

FQDN="$DNS_LABEL.$LOCATION.cloudapp.azure.com"
PUBLIC_URL="https://$FQDN"

# Create Let's Encrypt ClusterIssuer
echo ""
echo "Creating Let's Encrypt ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${FQDN}
    privateKeySecretRef:
      name: letsencrypt-key
    solvers:
    - http01:
        ingress:
          class: dapr
EOF
echo "  ClusterIssuer created"

# =========================================
# Azure AD (Entra ID) App Registration
# =========================================
echo ""
echo "========================================="
echo "Registering Azure AD App (Entra ID)"
echo "========================================="
echo ""

# Get tenant ID from current Azure login
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null)
if [ -z "$TENANT_ID" ]; then
    echo "ERROR: Not logged in to Azure. Run 'az login' first."
    exit 1
fi
echo "  Tenant ID: $TENANT_ID"

APP_DISPLAY_NAME="dapr-demo-frontend"

# Check if app registration already exists
EXISTING_APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null)

if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "None" ]; then
    echo "  App registration already exists: $EXISTING_APP_ID"
    AZURE_CLIENT_ID="$EXISTING_APP_ID"

    # Get object ID for Graph API updates
    APP_OBJECT_ID=$(az ad app show --id "$AZURE_CLIENT_ID" --query id -o tsv)

    # Update SPA redirect URIs (in case the public URL changed)
    echo "  Updating SPA redirect URIs..."
    az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
        --headers 'Content-Type=application/json' \
        --body "{
            \"spa\": {
                \"redirectUris\": [\"${PUBLIC_URL}/\", \"http://localhost:3000/\", \"http://localhost:8080/\"]
            }
        }" > /dev/null
    echo "  Redirect URIs updated"
else
    echo "  Creating app registration: $APP_DISPLAY_NAME"

    # Create app registration with SPA platform via Graph API
    APP_RESPONSE=$(az rest --method POST \
        --uri "https://graph.microsoft.com/v1.0/applications" \
        --headers 'Content-Type=application/json' \
        --body "{
            \"displayName\": \"${APP_DISPLAY_NAME}\",
            \"signInAudience\": \"AzureADMyOrg\",
            \"spa\": {
                \"redirectUris\": [\"${PUBLIC_URL}/\", \"http://localhost:3000/\", \"http://localhost:8080/\"]
            }
        }")

    AZURE_CLIENT_ID=$(echo "$APP_RESPONSE" | jq -r '.appId')
    APP_OBJECT_ID=$(echo "$APP_RESPONSE" | jq -r '.id')

    if [ -z "$AZURE_CLIENT_ID" ] || [ "$AZURE_CLIENT_ID" == "null" ]; then
        echo "ERROR: Failed to create app registration."
        echo "  You may not have sufficient Azure AD permissions."
        echo "  See the README for manual registration instructions."
        echo ""
        echo "  Continuing without Azure AD — deploy with --with-security later"
        echo "  after creating the app manually."
        AZURE_CLIENT_ID=""
    else
        echo "  Created app: $AZURE_CLIENT_ID"

        # Set identifier URI (required for API scopes)
        echo "  Setting identifier URI: api://$AZURE_CLIENT_ID"
        az rest --method PATCH \
            --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
            --headers 'Content-Type=application/json' \
            --body "{
                \"identifierUris\": [\"api://${AZURE_CLIENT_ID}\"]
            }" > /dev/null

        # Add access_as_user API scope
        SCOPE_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')
        echo "  Adding API scope: access_as_user"
        az rest --method PATCH \
            --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
            --headers 'Content-Type=application/json' \
            --body "{
                \"api\": {
                    \"oauth2PermissionScopes\": [{
                        \"id\": \"${SCOPE_ID}\",
                        \"adminConsentDescription\": \"Access the Dapr Demo API as the signed-in user\",
                        \"adminConsentDisplayName\": \"access_as_user\",
                        \"userConsentDescription\": \"Access the Dapr Demo API on your behalf\",
                        \"userConsentDisplayName\": \"Access API as you\",
                        \"isEnabled\": true,
                        \"type\": \"User\",
                        \"value\": \"access_as_user\"
                    }]
                }
            }" > /dev/null
        echo "  API scope added"
    fi
fi

# Save configuration for other scripts
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
cat > "$CONFIG_FILE" << EOF
# Azure configuration - generated by setup-cluster.sh
# Source this file in other scripts: source \$SCRIPT_DIR/../.azure-config
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
AKS_NAME="$AKS_NAME"
DNS_LABEL="$DNS_LABEL"
EXTERNAL_IP="$EXTERNAL_IP"
AZURE_CLIENT_ID="$AZURE_CLIENT_ID"
AZURE_TENANT_ID="$TENANT_ID"
EOF

echo ""
echo "========================================="
echo "Cluster Setup Complete!"
echo "========================================="
echo ""
echo "Resources:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  AKS Cluster:    $AKS_NAME"
echo ""
echo "Public access:"
echo "  IP Address: $EXTERNAL_IP"
echo "  URL: $PUBLIC_URL"
echo ""
if [ -n "$AZURE_CLIENT_ID" ]; then
echo "Azure AD (Entra ID):"
echo "  App Name:   $APP_DISPLAY_NAME"
echo "  Client ID:  $AZURE_CLIENT_ID"
echo "  Tenant ID:  $TENANT_ID"
echo "  Scope:      api://$AZURE_CLIENT_ID/access_as_user"
echo ""
echo "Next steps:"
echo "  1. ./scripts/deploy-all.sh --with-security"
echo "     (Azure AD client/tenant IDs are read from .azure-config automatically)"
else
echo "Azure AD: Not configured (see README for manual setup)"
echo ""
echo "Next steps:"
echo "  1. Register an Azure AD app manually (see README)"
echo "  2. ./scripts/deploy-all.sh --with-security --azure-client-id <ID> --azure-tenant-id <ID>"
fi
echo ""
echo "  Deploy without security:"
echo "    ./scripts/deploy-all.sh --with-frontend"
echo ""
echo "Configuration saved to: $CONFIG_FILE"
echo "========================================="
