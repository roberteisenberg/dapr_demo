#!/bin/bash
set -euo pipefail

# Configure APIs in Azure API Management
# This script imports API definitions and applies policies

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

# Default values
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dapr-demo}"
APIM_NAME="${APIM_NAME:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --apim-name)
            APIM_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --resource-group NAME  Azure resource group (default: rg-dapr-demo)"
            echo "  --apim-name NAME       APIM instance name (required)"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$APIM_NAME" ]]; then
    # Try to get from Terraform
    if [[ -d "$PROJECT_ROOT/terraform" ]]; then
        cd "$PROJECT_ROOT/terraform"
        APIM_NAME=$(terraform output -raw apim_name 2>/dev/null || echo "")
        cd "$PROJECT_ROOT"
    fi

    if [[ -z "$APIM_NAME" ]]; then
        log_error "APIM name is required. Use --apim-name or run terraform apply"
        exit 1
    fi
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi

    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure CLI. Run: az login"
        exit 1
    fi

    # Check if APIM exists
    if ! az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "APIM instance '$APIM_NAME' not found in resource group '$RESOURCE_GROUP'"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Apply global policy
apply_global_policy() {
    log_info "Applying global policy..."

    az apim update \
        --name "$APIM_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --set "properties.policies=@$PROJECT_ROOT/policies/global-policy.xml" \
        --output none 2>/dev/null || true

    # Alternative: use REST API for global policy
    POLICY_CONTENT=$(cat "$PROJECT_ROOT/policies/global-policy.xml")

    az rest --method PUT \
        --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/policies/policy?api-version=2022-08-01" \
        --body "{\"properties\": {\"value\": $(echo "$POLICY_CONTENT" | jq -Rs .), \"format\": \"xml\"}}" \
        --output none 2>/dev/null || log_warning "Could not apply global policy via REST"

    log_success "Global policy applied"
}

# Import Catalog API
import_catalog_api() {
    log_info "Importing Catalog API..."

    # Create or update API
    az apim api import \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --api-id "catalog-api" \
        --path "v1/catalog" \
        --specification-format OpenApi \
        --specification-path "$PROJECT_ROOT/api-definitions/catalog-api.json" \
        --display-name "Catalog API" \
        --protocols https http \
        --subscription-required false \
        --output none

    # Apply API-specific policy
    az apim api operation policy create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --api-id "catalog-api" \
        --operation-id "listProducts" \
        --xml-policy "@$PROJECT_ROOT/policies/catalog-policy.xml" \
        --output none 2>/dev/null || true

    # Apply policy at API level
    az rest --method PUT \
        --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/catalog-api/policies/policy?api-version=2022-08-01" \
        --body "{\"properties\": {\"value\": $(cat "$PROJECT_ROOT/policies/catalog-policy.xml" | jq -Rs .), \"format\": \"xml\"}}" \
        --output none

    log_success "Catalog API imported"
}

# Import Orders API
import_orders_api() {
    log_info "Importing Orders API..."

    # Create or update API
    az apim api import \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --api-id "orders-api" \
        --path "v1/orders" \
        --specification-format OpenApi \
        --specification-path "$PROJECT_ROOT/api-definitions/orders-api.json" \
        --display-name "Orders API" \
        --protocols https http \
        --subscription-required true \
        --output none

    # Apply policy at API level
    az rest --method PUT \
        --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/orders-api/policies/policy?api-version=2022-08-01" \
        --body "{\"properties\": {\"value\": $(cat "$PROJECT_ROOT/policies/orders-policy.xml" | jq -Rs .), \"format\": \"xml\"}}" \
        --output none

    log_success "Orders API imported"
}

# Create product and subscription for Orders API
create_subscription() {
    log_info "Creating subscription for Orders API..."

    # Create product (if not exists)
    az apim product create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --product-id "dapr-demo-product" \
        --display-name "Dapr Demo Product" \
        --description "Access to Dapr Demo APIs" \
        --state published \
        --subscription-required true \
        --approval-required false \
        --output none 2>/dev/null || true

    # Associate Orders API with product
    az apim product api add \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --product-id "dapr-demo-product" \
        --api-id "orders-api" \
        --output none 2>/dev/null || true

    # Create subscription
    az apim subscription create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --subscription-id "dapr-demo-sub" \
        --display-name "Dapr Demo Subscription" \
        --scope "/products/dapr-demo-product" \
        --state active \
        --output none 2>/dev/null || true

    # Get subscription key
    SUB_KEY=$(az apim subscription keys list \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --subscription-id "dapr-demo-sub" \
        --query primaryKey -o tsv 2>/dev/null || echo "")

    if [[ -n "$SUB_KEY" ]]; then
        log_success "Subscription created. Primary key: $SUB_KEY"
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "APIM API Configuration"
    echo "=========================================="
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo "APIM Name:      $APIM_NAME"
    echo ""

    check_prerequisites
    apply_global_policy
    import_catalog_api
    import_orders_api
    create_subscription

    echo ""
    log_success "API configuration complete!"
    echo ""
}

main "$@"
