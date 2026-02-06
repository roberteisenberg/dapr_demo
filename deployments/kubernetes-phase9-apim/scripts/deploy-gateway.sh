#!/bin/bash
set -euo pipefail

# Deploy Azure API Management Self-Hosted Gateway to AKS
# Prerequisites: Terraform outputs available, AKS cluster accessible

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Get gateway configuration from Terraform or environment
get_gateway_config() {
    log_info "Getting gateway configuration..."

    # Try to get from Terraform outputs
    if [[ -d "$PROJECT_ROOT/terraform" ]]; then
        cd "$PROJECT_ROOT/terraform"

        if terraform output -json &> /dev/null; then
            CONFIG_ENDPOINT=$(terraform output -raw config_endpoint 2>/dev/null || echo "")
            GATEWAY_TOKEN=$(terraform output -raw gateway_token 2>/dev/null || echo "")
        fi

        cd "$PROJECT_ROOT"
    fi

    # Fall back to environment variables
    CONFIG_ENDPOINT="${CONFIG_ENDPOINT:-$APIM_CONFIG_ENDPOINT}"
    GATEWAY_TOKEN="${GATEWAY_TOKEN:-$APIM_GATEWAY_TOKEN}"

    if [[ -z "$CONFIG_ENDPOINT" ]]; then
        log_error "APIM config endpoint not found. Set APIM_CONFIG_ENDPOINT or run terraform apply"
        exit 1
    fi

    if [[ -z "$GATEWAY_TOKEN" ]]; then
        log_error "Gateway token not found. Set APIM_GATEWAY_TOKEN or run terraform apply"
        exit 1
    fi

    log_success "Gateway configuration retrieved"
}

# Create namespace and deploy gateway
deploy_gateway() {
    log_info "Deploying APIM self-hosted gateway..."

    # Apply base manifests (namespace, deployment, LoadBalancer service)
    kubectl apply -f "$PROJECT_ROOT/k8s/apim-gateway.yaml"

    # Wait for namespace
    kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/apim-gateway --timeout=30s

    # Update ConfigMap with config endpoint
    log_info "Configuring gateway endpoint: $CONFIG_ENDPOINT"
    kubectl create configmap apim-gateway-env \
        --from-literal=config.service.endpoint="$CONFIG_ENDPOINT" \
        --namespace=apim-gateway \
        --dry-run=client -o yaml | kubectl apply -f -

    # Update Secret with gateway token
    log_info "Configuring gateway authentication..."
    GATEWAY_TOKEN_B64=$(echo -n "GatewayKey $GATEWAY_TOKEN" | base64 -w 0)
    kubectl create secret generic apim-gateway-token \
        --from-literal=value="$GATEWAY_TOKEN_B64" \
        --namespace=apim-gateway \
        --dry-run=client -o yaml | kubectl apply -f -

    # Restart deployment to pick up new config
    kubectl rollout restart deployment/apim-gateway -n apim-gateway

    log_success "Gateway deployment initiated"
}

# Wait for gateway to be ready
wait_for_gateway() {
    log_info "Waiting for gateway pods to be ready..."

    kubectl rollout status deployment/apim-gateway -n apim-gateway --timeout=300s

    # Verify pods are running
    READY_PODS=$(kubectl get pods -n apim-gateway -l app=apim-gateway \
        -o jsonpath='{.items[*].status.containerStatuses[?(@.name=="apim-gateway")].ready}' | tr ' ' '\n' | grep -c true || echo 0)

    if [[ "$READY_PODS" -ge 1 ]]; then
        log_success "Gateway is ready with $READY_PODS pod(s)"
    else
        log_error "Gateway pods are not ready"
        kubectl get pods -n apim-gateway
        exit 1
    fi
}

# Get gateway URL
get_gateway_url() {
    log_info "Getting gateway URL from LoadBalancer service..."

    # Wait for LoadBalancer to get an external IP
    for i in {1..30}; do
        GATEWAY_IP=$(kubectl get svc apim-gateway -n apim-gateway \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [[ -n "$GATEWAY_IP" ]]; then
            break
        fi

        log_info "Waiting for LoadBalancer IP... ($i/30)"
        sleep 10
    done

    if [[ -n "$GATEWAY_IP" ]]; then
        log_success "Gateway available at: http://$GATEWAY_IP"
        echo ""
        echo "API Endpoints:"
        echo "  Catalog: http://$GATEWAY_IP/api/v1/catalog"
        echo "  Orders:  http://$GATEWAY_IP/api/v1/orders"
        echo ""
        echo "DNS (after propagation):"
        echo "  http://dapr-demo-api.eastus.cloudapp.azure.com/api/v1/..."
    else
        log_warning "LoadBalancer IP not yet assigned. Check with: kubectl get svc -n apim-gateway"
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "APIM Self-Hosted Gateway Deployment"
    echo "=========================================="
    echo ""

    check_prerequisites
    get_gateway_config
    deploy_gateway
    wait_for_gateway
    get_gateway_url

    echo ""
    log_success "Deployment complete!"
    echo ""
}

main "$@"
