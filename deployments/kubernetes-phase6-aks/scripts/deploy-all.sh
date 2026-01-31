#!/bin/bash
# Deploy all services to AKS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

# Load Azure configuration
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Azure configuration not found."
    echo "Run ./scripts/setup-azure.sh first."
    exit 1
fi

# Defaults
WITH_FRONTEND=false
PUBSUB_BACKEND="redis"
STATESTORE_BACKEND="redis"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-frontend)
            WITH_FRONTEND=true
            shift
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
            echo "Usage: $0 [--with-frontend] [--pubsub redis|rabbitmq] [--statestore redis|mongodb]"
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

echo "========================================="
echo "Deploying to Azure Kubernetes Service"
echo "========================================="
echo "Registry:    Docker Hub (reisenberg100/dapr-*)"
echo "Pub/Sub:     $PUBSUB_BACKEND"
echo "State Store: $STATESTORE_BACKEND"
echo "Frontend:    $WITH_FRONTEND"
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

# Deploy services
echo "Deploying services..."
apply_manifest "$MANIFESTS_DIR/04-catalog-service.yaml"
apply_manifest "$MANIFESTS_DIR/05-order-service.yaml"
apply_manifest "$MANIFESTS_DIR/06-notification-service.yaml"
apply_manifest "$MANIFESTS_DIR/07-workflow-service.yaml"

# Deploy frontend (optional)
if [[ "$WITH_FRONTEND" == "true" ]]; then
    echo "Deploying web-app..."
    apply_manifest "$MANIFESTS_DIR/08-web-app.yaml"
fi

# Deploy ingress
echo "Deploying ingress..."
kubectl apply -f "$MANIFESTS_DIR/09-ingress.yaml"

# Wait for services
echo "Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/catalog-service -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/order-service -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/notification-service -n dapr-demo
kubectl wait --for=condition=available --timeout=300s deployment/workflow-service -n dapr-demo

if [[ "$WITH_FRONTEND" == "true" ]]; then
    kubectl wait --for=condition=available --timeout=300s deployment/web-app -n dapr-demo
fi

# Get public URL
PUBLIC_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Pub/Sub:     $PUBSUB_BACKEND"
echo "  State Store: $STATESTORE_BACKEND"
echo "  Frontend:    $WITH_FRONTEND"
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
