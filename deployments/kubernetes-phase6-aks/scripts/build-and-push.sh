#!/bin/bash
# Build images and push to Docker Hub
# Uses local Docker to build, then pushes to Docker Hub

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$SCRIPT_DIR/../../../services"
FRONTEND_DIR="$SCRIPT_DIR/../../../frontend"

DOCKER_REGISTRY="reisenberg100"

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
echo "Building Images for Docker Hub"
echo "========================================="
echo ""
echo "Registry: $DOCKER_REGISTRY"
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

# Verify Docker Hub login
echo "Verifying Docker Hub login..."
if ! docker info 2>/dev/null | grep -q "Username"; then
    echo "WARNING: Not logged in to Docker Hub."
    echo "Run 'docker login' first if push fails."
fi
echo ""

# Build and push each service
SERVICES=("catalog-service" "order-service" "notification-service" "workflow-service")

for SERVICE in "${SERVICES[@]}"; do
    echo "Building and pushing $SERVICE..."
    docker build -t "$DOCKER_REGISTRY/dapr-$SERVICE:latest" "$SERVICES_DIR/$SERVICE"
    docker push "$DOCKER_REGISTRY/dapr-$SERVICE:latest"
    echo ""
done

if [[ "$WITH_FRONTEND" == "true" ]]; then
    echo "Building and pushing web-app..."
    if [[ -d "$FRONTEND_DIR/web-app" ]]; then
        docker build -t "$DOCKER_REGISTRY/dapr-web-app:latest" "$FRONTEND_DIR/web-app"
        docker push "$DOCKER_REGISTRY/dapr-web-app:latest"
    else
        echo "  WARNING: frontend/web-app/ not found, skipping"
    fi
    echo ""
fi

echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "Images pushed to Docker Hub ($DOCKER_REGISTRY):"
for SERVICE in "${SERVICES[@]}"; do
    echo "  - $DOCKER_REGISTRY/dapr-$SERVICE:latest"
done
if [[ "$WITH_FRONTEND" == "true" ]]; then
    echo "  - $DOCKER_REGISTRY/dapr-web-app:latest"
fi
echo ""
echo "Next step: ./scripts/deploy-all.sh [--with-frontend] [--pubsub redis|rabbitmq] [--statestore redis|mongodb]"
echo "========================================="
