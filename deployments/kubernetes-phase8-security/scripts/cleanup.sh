#!/bin/bash
# Delete all Azure resources using Terraform
# WARNING: This destroys the entire infrastructure!

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"

echo "========================================="
echo "Azure Cleanup (Terraform)"
echo "========================================="
echo ""

# Kill any existing port-forwards
echo "Stopping port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true

# Check if Terraform state exists
if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    echo "No Terraform state found. Nothing to clean up."
    exit 0
fi

# Show what will be destroyed
cd "$TERRAFORM_DIR"
echo "The following resources will be DESTROYED:"
echo ""
terraform show -no-color | grep -E "^# azurerm_" | sed 's/^# /  /' || echo "  (unable to list resources)"
echo ""
echo "WARNING: This action is IRREVERSIBLE!"
echo ""
read -p "Are you sure you want to destroy all resources? (yes/no) " -r
echo

if [[ ! $REPLY == "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Remove kubectl context first
echo "Removing kubectl context..."
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
AKS_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "")
if [ -n "$AKS_NAME" ]; then
    kubectl config delete-context "$AKS_NAME" 2>/dev/null || true
    kubectl config delete-cluster "$AKS_NAME" 2>/dev/null || true
fi

# Destroy infrastructure
echo ""
echo "Destroying Azure resources with Terraform..."
echo "This may take several minutes..."
terraform destroy -auto-approve

# Remove local config
rm -f "$CONFIG_FILE"
echo ""
echo "Local configuration removed."

echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
echo ""
echo "All Azure resources have been destroyed."
echo "========================================="
