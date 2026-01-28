#!/bin/bash
# Build images and push to Azure Container Registry
# Uses local Docker to build, then pushes to ACR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$SCRIPT_DIR/../../../services"
FRONTEND_DIR="$SCRIPT_DIR/../../../frontend"

# Load Azure configuration
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Azure configuration not found."
    echo "Run ./scripts/setup-cluster.sh first."
    exit 1
fi

# Parse arguments
WITH_FRONTEND=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-frontend)
            WITH_FRONTEND=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--with-frontend]"
            exit 1
            ;;
    esac
done

echo "========================================="
echo "Building Images for Azure Container Registry"
echo "========================================="
echo ""
echo "ACR: $ACR_LOGIN_SERVER"
echo "Frontend: $WITH_FRONTEND"
echo ""

# Verify Docker is running
echo "Checking Docker..."
if ! docker info &> /dev/null; then
    echo "ERROR: Docker is not running."
    echo "Please start Docker Desktop and try again."
    exit 1
fi
echo "  Docker: OK"

# Login to ACR
echo "Logging in to ACR..."
az acr login --name "$ACR_NAME"
echo "  ACR login successful"
echo ""

# Build and push each service
echo "Building and pushing catalog-service..."
docker build -t "$ACR_LOGIN_SERVER/catalog-service:latest" "$SERVICES_DIR/catalog-service"
docker push "$ACR_LOGIN_SERVER/catalog-service:latest"

echo ""
echo "Building and pushing order-service..."
docker build -t "$ACR_LOGIN_SERVER/order-service:latest" "$SERVICES_DIR/order-service"
docker push "$ACR_LOGIN_SERVER/order-service:latest"

echo ""
echo "Building and pushing notification-service..."
docker build -t "$ACR_LOGIN_SERVER/notification-service:latest" "$SERVICES_DIR/notification-service"
docker push "$ACR_LOGIN_SERVER/notification-service:latest"

echo ""
echo "Building and pushing workflow-service..."
docker build -t "$ACR_LOGIN_SERVER/workflow-service:latest" "$SERVICES_DIR/workflow-service"
docker push "$ACR_LOGIN_SERVER/workflow-service:latest"

if [[ "$WITH_FRONTEND" == "true" ]]; then
    echo ""
    echo "Building and pushing web-app..."
    if [[ -d "$FRONTEND_DIR/web-app" ]]; then
        docker build -t "$ACR_LOGIN_SERVER/web-app:latest" "$FRONTEND_DIR/web-app"
        docker push "$ACR_LOGIN_SERVER/web-app:latest"
    else
        echo "  WARNING: frontend/web-app/ not found, skipping"
    fi
fi

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "Images in ACR:"
az acr repository list --name "$ACR_NAME" --output table
echo ""
echo "Next step: ./scripts/deploy-all.sh"
echo "========================================="
