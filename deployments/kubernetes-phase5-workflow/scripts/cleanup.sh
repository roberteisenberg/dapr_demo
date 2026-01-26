#!/bin/bash
# Remove all Kubernetes resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo "========================================="
echo "Cleaning up Kubernetes resources"
echo "========================================="
echo ""

# Check if namespace exists
if ! kubectl get namespace dapr-demo &> /dev/null; then
    echo "Namespace dapr-demo does not exist. Nothing to clean up."
    exit 0
fi

echo "Deleting all resources in dapr-demo namespace..."

# Delete in reverse order
kubectl delete -f "$MANIFESTS_DIR/09-ingress.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/08-web-app.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/06-notification-service.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/05-order-service.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/04-catalog-service.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/03-components/" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/02-mongodb.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/02-rabbitmq.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS_DIR/01-redis.yaml" --ignore-not-found

# Uninstall nginx-ingress
echo "Uninstalling nginx-ingress..."
helm uninstall api-gateway -n dapr-demo 2>/dev/null || echo "  nginx-ingress not installed"

# Delete namespace
echo "Deleting namespace..."
kubectl delete namespace dapr-demo --ignore-not-found

echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
echo ""
echo "To fully reset:"
echo "  minikube delete"
echo ""
echo "To keep cluster but uninstall Dapr:"
echo "  dapr uninstall -k"
echo "========================================="
