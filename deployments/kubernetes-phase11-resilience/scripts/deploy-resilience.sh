#!/bin/bash
# Phase 11: Deploy resilience features on top of the existing AKS deployment.
# Prerequisite: Phase 10 (which implies Phases 6-9 deployed)
#
# Applies:
#   1. Dapr Resiliency CRD (retries, timeouts, circuit breakers)
#   2. Updated tracing Configuration (adds /dead-letters to access control)
#   3. Horizontal Pod Autoscalers for catalog-service and order-service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo "========================================="
echo "Phase 11: Deploying Resilience Features"
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
        echo "ERROR: $svc deployment not found. Deploy Phases 6-10 first."
        exit 1
    fi
done
echo "  All services present."
echo ""

# 1. Apply Dapr Resiliency policy
echo "1. Applying Dapr Resiliency policy..."
kubectl apply -f "$MANIFESTS_DIR/resiliency.yaml"
echo ""

# 2. Update tracing Configuration (adds /dead-letters to access control)
echo "2. Updating tracing Configuration (access control for /dead-letters)..."
kubectl apply -f "$MANIFESTS_DIR/tracing.yaml"
echo ""

# 3. Apply Horizontal Pod Autoscalers
echo "3. Applying Horizontal Pod Autoscalers..."
kubectl apply -f "$MANIFESTS_DIR/hpa.yaml"
echo ""

# 4. Restart services to pick up new resiliency policy
echo "4. Restarting services to load resiliency policy..."
kubectl rollout restart deployment/catalog-service -n dapr-demo
kubectl rollout restart deployment/order-service -n dapr-demo
kubectl rollout restart deployment/notification-service -n dapr-demo
kubectl rollout restart deployment/workflow-service -n dapr-demo

echo "  Waiting for rollouts..."
for svc in catalog-service order-service notification-service workflow-service; do
    kubectl rollout status deployment/$svc -n dapr-demo --timeout=120s
done
echo ""

echo "========================================="
echo "Phase 11: Resilience Deployed"
echo "========================================="
echo ""
echo "Resources:"
echo "  Resiliency policy:  kubectl get resiliency -n dapr-demo"
echo "  HPAs:               kubectl get hpa -n dapr-demo"
echo "  Dead letters:       curl <URL>/v1.0/invoke/notification-service/method/dead-letters"
echo ""
echo "Demo scripts:"
echo "  ./scripts/demo-circuit-breaker.sh   # Kill service, watch circuit breaker + recovery"
echo "  ./scripts/demo-dead-letter.sh       # Poison message -> dead letter topic"
echo "  ./scripts/demo-hpa-load.sh          # Load test -> HPA scales pods"
echo ""
echo "Test:"
echo "  ./scripts/test-resilience.sh        # Automated resilience tests"
echo "========================================="
