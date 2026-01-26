#!/bin/bash
# Build Docker images in minikube's Docker environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$SCRIPT_DIR/../../../services"
FRONTEND_DIR="$SCRIPT_DIR/../../../frontend"

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
echo "Building Images for Minikube"
echo "========================================="
echo ""

# Check if we're in minikube's Docker environment
if [[ -z "$MINIKUBE_ACTIVE_DOCKERD" ]]; then
    echo "WARNING: Not in minikube's Docker environment"
    echo "Run: eval \$(minikube docker-env)"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

cd "$SERVICES_DIR"

echo "Building catalog-service..."
docker build -t catalog-service:latest -f catalog-service/Dockerfile catalog-service/

echo "Building order-service..."
docker build -t order-service:latest -f order-service/Dockerfile order-service/

echo "Building notification-service..."
docker build -t notification-service:latest -f notification-service/Dockerfile notification-service/

if [[ "$WITH_FRONTEND" == "true" ]]; then
    echo "Building web-app..."
    if [[ -d "$FRONTEND_DIR/web-app" ]]; then
        cd "$FRONTEND_DIR"
        docker build -t web-app:latest -f web-app/Dockerfile web-app/
    else
        echo "  WARNING: frontend/web-app/ not found, skipping"
    fi
fi

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "Images built:"
docker images | grep -E "(catalog|order|notification)-service|web-app" | head -10
echo ""
echo "Next step: ./scripts/deploy-all.sh"
