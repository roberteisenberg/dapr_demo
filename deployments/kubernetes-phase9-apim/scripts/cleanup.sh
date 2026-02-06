#!/bin/bash
set -euo pipefail

# Cleanup Phase 9 APIM resources
# Removes self-hosted gateway from AKS and optionally Azure resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Options
CLEANUP_K8S=true
CLEANUP_AZURE=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --k8s-only)
            CLEANUP_K8S=true
            CLEANUP_AZURE=false
            shift
            ;;
        --azure-only)
            CLEANUP_K8S=false
            CLEANUP_AZURE=true
            shift
            ;;
        --all)
            CLEANUP_K8S=true
            CLEANUP_AZURE=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --k8s-only    Only cleanup Kubernetes resources (default)"
            echo "  --azure-only  Only cleanup Azure APIM resources"
            echo "  --all         Cleanup both K8s and Azure resources"
            echo "  --force, -f   Skip confirmation prompts"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Confirm action
confirm() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    local message="$1"
    read -p "$message [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Cleanup Kubernetes resources
cleanup_k8s() {
    log_info "Cleaning up Kubernetes resources..."

    if ! kubectl cluster-info &> /dev/null; then
        log_warning "Cannot connect to Kubernetes cluster, skipping K8s cleanup"
        return
    fi

    # Check if namespace exists
    if kubectl get namespace apim-gateway &> /dev/null; then
        if confirm "Delete apim-gateway namespace and all resources?"; then
            kubectl delete namespace apim-gateway --wait=true
            log_success "Kubernetes resources deleted"
        else
            log_info "Skipping Kubernetes cleanup"
        fi
    else
        log_info "Namespace apim-gateway not found, nothing to clean"
    fi
}

# Cleanup Azure APIM resources via Terraform
cleanup_azure() {
    log_info "Cleaning up Azure APIM resources..."

    if [[ ! -d "$PROJECT_ROOT/terraform" ]]; then
        log_warning "Terraform directory not found, skipping Azure cleanup"
        return
    fi

    cd "$PROJECT_ROOT/terraform"

    if [[ ! -f "terraform.tfstate" ]]; then
        log_info "No Terraform state found, nothing to destroy"
        return
    fi

    if confirm "Destroy Azure APIM resources via Terraform?"; then
        log_warning "This will destroy:"
        terraform plan -destroy -compact-warnings 2>/dev/null | grep -E "^  #|will be destroyed" || true

        if confirm "Proceed with terraform destroy?"; then
            terraform destroy -auto-approve
            log_success "Azure resources destroyed"
        else
            log_info "Skipping Terraform destroy"
        fi
    else
        log_info "Skipping Azure cleanup"
    fi

    cd "$PROJECT_ROOT"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "Phase 9 APIM Cleanup"
    echo "=========================================="
    echo ""

    if [[ "$CLEANUP_K8S" == "true" ]]; then
        cleanup_k8s
    fi

    if [[ "$CLEANUP_AZURE" == "true" ]]; then
        cleanup_azure
    fi

    echo ""
    log_success "Cleanup complete!"
    echo ""
}

main "$@"
