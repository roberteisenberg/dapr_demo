#!/bin/bash
set -euo pipefail

# Deploy APIM ingress rule to AKS
# Creates a new Ingress path (/apim/v1.0/*) that APIM cloud gateway routes through.
# The /apim prefix is stripped by nginx rewrite-target so Dapr receives standard URLs.
#
# Prerequisites: AKS cluster running with Phase 6/7/8 deployed, nginx-ingress installed

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

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Verify dapr-demo namespace exists
    if ! kubectl get namespace dapr-demo &> /dev/null; then
        log_error "Namespace dapr-demo not found. Deploy Phase 6/7/8 first."
        exit 1
    fi

    # Verify api-gateway-dapr service exists
    if ! kubectl get svc api-gateway-dapr -n dapr-demo &> /dev/null; then
        log_error "Service api-gateway-dapr not found. Deploy Phase 6/7/8 first."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Detect the nginx-ingress FQDN
detect_fqdn() {
    log_info "Detecting nginx-ingress FQDN..."

    FQDN=""

    # Try Phase 8 .azure-config first
    PHASE8_CONFIG="$PROJECT_ROOT/../../deployments/kubernetes-phase8-security/.azure-config"
    PHASE6_CONFIG="$PROJECT_ROOT/../../deployments/kubernetes-phase6-aks/.azure-config"

    for config_file in "$PHASE8_CONFIG" "$PHASE6_CONFIG"; do
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            if [[ -n "${DNS_LABEL:-}" && -n "${LOCATION:-}" ]]; then
                FQDN="$DNS_LABEL.$LOCATION.cloudapp.azure.com"
                log_info "FQDN from config: $FQDN"
                return
            fi
        fi
    done

    # Fall back: read DNS label from the nginx-ingress LoadBalancer service
    DNS_LABEL=$(kubectl get svc -n dapr-demo -l app.kubernetes.io/name=ingress-nginx \
        -o jsonpath='{.items[0].metadata.annotations.service\.beta\.kubernetes\.io/azure-dns-label-name}' 2>/dev/null || echo "")

    if [[ -n "$DNS_LABEL" ]]; then
        # Detect region from the service's external IP FQDN or default to eastus
        LOCATION=$(kubectl get svc -n dapr-demo -l app.kubernetes.io/name=ingress-nginx \
            -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null | \
            sed 's/.*\.\([a-z]*\)\.cloudapp.*/\1/' || echo "eastus")
        FQDN="$DNS_LABEL.$LOCATION.cloudapp.azure.com"
        log_info "FQDN from kubectl: $FQDN"
        return
    fi

    # Fall back: use terraform output
    if [[ -d "$PROJECT_ROOT/terraform" ]]; then
        FQDN=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw nginx_ingress_fqdn 2>/dev/null || echo "")
        if [[ -n "$FQDN" ]]; then
            log_info "FQDN from terraform: $FQDN"
            return
        fi
    fi

    log_error "Cannot detect nginx-ingress FQDN."
    log_error "Ensure Phase 6/7/8 is deployed, or set FQDN environment variable."
    exit 1
}

# Deploy the APIM ingress
deploy_ingress() {
    log_info "Deploying APIM ingress rule..."

    # Substitute FQDN placeholder and apply
    sed "s/FQDN_PLACEHOLDER/$FQDN/g" "$PROJECT_ROOT/k8s/apim-ingress.yaml" | kubectl apply -f -

    log_success "APIM ingress deployed"
}

# Verify the ingress
verify_ingress() {
    log_info "Verifying APIM ingress..."

    # Wait for ingress to get an address
    for i in {1..12}; do
        ADDRESS=$(kubectl get ingress dapr-demo-ingress-apim -n dapr-demo \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [[ -n "$ADDRESS" ]]; then
            break
        fi

        log_info "Waiting for ingress address... ($i/12)"
        sleep 5
    done

    echo ""
    if [[ -n "$ADDRESS" ]]; then
        log_success "APIM ingress is active at $ADDRESS"
    else
        log_warning "Ingress address not yet assigned. It may take a moment."
    fi

    echo ""
    echo "APIM cloud gateway should route through:"
    echo "  https://$FQDN/apim/v1.0/invoke/{service}/method/{endpoint}"
    echo ""
    echo "nginx-ingress strips /apim, so Dapr receives:"
    echo "  /v1.0/invoke/{service}/method/{endpoint}"
    echo ""
    echo "APIM gateway URL (from terraform output):"
    echo "  cd terraform && terraform output apim_gateway_url"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "APIM Ingress Deployment"
    echo "=========================================="
    echo ""

    # Allow FQDN override via environment variable
    if [[ -n "${FQDN:-}" ]]; then
        log_info "Using FQDN from environment: $FQDN"
    else
        detect_fqdn
    fi

    check_prerequisites
    deploy_ingress
    verify_ingress

    echo ""
    log_success "Deployment complete!"
    echo ""
}

main "$@"
