#!/bin/bash
# Phase 12: Deploy actor-enabled services on top of the existing AKS deployment.
# Prerequisite: Phase 11 (which implies Phases 6-10 deployed)
#
# Phase 12 adds no new Kubernetes manifests — actor support is built into Dapr.
# The changes are service code only:
#   - catalog-service: ProductActor (Go) for stock management
#   - workflow-service: Actor invocation for Reserve/Release inventory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../../../.."

echo "========================================="
echo "Phase 12: Deploying Actor-Enabled Services"
echo "========================================="
echo ""

# Verify cluster connectivity
echo "Checking cluster connectivity..."
if ! kubectl get namespace dapr-demo &>/dev/null; then
    echo "ERROR: Cannot reach dapr-demo namespace."
    echo "Make sure your AKS cluster is running and kubectl is configured."
    echo "  az aks get-credentials --resource-group <rg> --cluster-name <cluster>"
    exit 1
fi
echo "  Connected to cluster."
echo ""

# Verify prerequisite services are running
echo "Checking prerequisite services..."
for svc in catalog-service order-service notification-service workflow-service; do
    if ! kubectl get deployment "$svc" -n dapr-demo &>/dev/null; then
        echo "ERROR: $svc deployment not found. Deploy Phases 6-11 first."
        exit 1
    fi
done
echo "  All services present."
echo ""

# Verify Dapr placement service is running (required for actors)
echo "Checking Dapr placement service..."
if kubectl get pods -n dapr-system -l app=dapr-placement-server --no-headers 2>/dev/null | grep -q Running; then
    echo "  Dapr placement service running."
else
    echo "  WARNING: Dapr placement service not found or not running."
    echo "  Actors require the placement service. Check: kubectl get pods -n dapr-system"
fi
echo ""

# Verify statestore has actorStateStore enabled
echo "Checking statestore configuration..."
ACTOR_STORE=$(kubectl get component statestore -n dapr-demo -o jsonpath='{.spec.metadata[?(@.name=="actorStateStore")].value}' 2>/dev/null || echo "")
if [[ "$ACTOR_STORE" == "true" ]]; then
    echo "  statestore has actorStateStore: true"
else
    echo "  WARNING: statestore may not have actorStateStore enabled."
    echo "  Check: kubectl get component statestore -n dapr-demo -o yaml"
fi
echo ""

# Remind about Docker images
echo "========================================="
echo "IMPORTANT: Rebuild Docker images before continuing."
echo ""
echo "catalog-service and workflow-service have code changes."
echo "Rebuild and push:"
echo ""
echo "  docker build -t <your-dockerhub>/dapr-catalog-service:latest services/catalog-service"
echo "  docker push <your-dockerhub>/dapr-catalog-service:latest"
echo ""
echo "  docker build -t <your-dockerhub>/dapr-workflow-service:latest services/workflow-service"
echo "  docker push <your-dockerhub>/dapr-workflow-service:latest"
echo ""
echo "Or use the Phase 8 build-and-push.sh script."
echo "========================================="
echo ""

read -p "Have you rebuilt and pushed the Docker images? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please rebuild and push the images first, then re-run this script."
    exit 0
fi

# Restart services to pick up new images
echo ""
echo "Restarting catalog-service and workflow-service..."
kubectl rollout restart deployment/catalog-service -n dapr-demo
kubectl rollout restart deployment/workflow-service -n dapr-demo

echo "  Waiting for rollouts..."
kubectl rollout status deployment/catalog-service -n dapr-demo --timeout=120s
kubectl rollout status deployment/workflow-service -n dapr-demo --timeout=120s
echo ""

# Verify actor registration
echo "Verifying actor registration..."
sleep 5  # Give the sidecar time to register with placement
ACTOR_CONFIG=$(kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- http://localhost:3500/v1.0/metadata 2>/dev/null || echo "{}")
if echo "$ACTOR_CONFIG" | grep -q "ProductActorType"; then
    echo "  ProductActorType registered successfully."
else
    echo "  WARNING: ProductActorType not found in metadata."
    echo "  It may take a moment. Check: kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- wget -q -O- http://localhost:3500/v1.0/metadata"
fi
echo ""

echo "========================================="
echo "Phase 12: Actors Deployed"
echo "========================================="
echo ""
echo "What's new:"
echo "  - catalog-service hosts ProductActorType (Reserve, Release, GetStock, InitStock)"
echo "  - workflow-service uses actor invocation for inventory operations"
echo "  - Creating/updating products via REST automatically initializes actor stock"
echo ""
echo "Demo scripts:"
echo "  ./scripts/demo-actor-concurrency.sh   # Concurrent orders, no race conditions"
echo ""
echo "Test:"
echo "  ./scripts/test-actors.sh              # Automated actor tests"
echo "========================================="
