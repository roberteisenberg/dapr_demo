#!/bin/bash
# Demo: Load test -> HPA scales pods up -> verify in Zipkin
#
# Requires 'hey' (HTTP load generator):
#   go install github.com/rakyll/hey@latest
#   brew install hey
#   sudo apt-get install hey

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    BASE_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
else
    for phase_dir in kubernetes-phase8-security kubernetes-phase6-aks; do
        alt_config="$SCRIPT_DIR/../../$phase_dir/.azure-config"
        if [ -f "$alt_config" ]; then
            source "$alt_config"
            BASE_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
            break
        fi
    done
    if [ -z "$BASE_URL" ]; then
        BASE_URL="http://localhost:8080"
    fi
fi

DAPR_API="$BASE_URL/v1.0/invoke"

# Check if hey is installed
if ! command -v hey &>/dev/null; then
    echo "ERROR: 'hey' is not installed."
    echo ""
    echo "Install with one of:"
    echo "  go install github.com/rakyll/hey@latest"
    echo "  brew install hey"
    echo "  sudo apt-get install hey"
    exit 1
fi

echo "========================================="
echo "Demo: HPA Auto-Scaling Under Load"
echo "========================================="
echo ""

# Seed a product so GET /products returns data
echo "Step 0: Seeding test product..."
curl -s -X POST "$DAPR_API/catalog-service/method/products" \
  -H 'Content-Type: application/json' \
  -d '{"id":"hpa-test","name":"HPA Test Product","price":10.00,"stock":1000}' > /dev/null 2>&1
echo "  Done."
echo ""

# Step 1: Baseline
echo "Step 1: Baseline -- current pod counts and HPA status"
echo ""
echo "  Pods:"
kubectl get pods -n dapr-demo -l app=catalog-service --no-headers 2>/dev/null | while read line; do echo "    $line"; done
echo ""
echo "  HPA:"
kubectl get hpa -n dapr-demo --no-headers 2>/dev/null | while read line; do echo "    $line"; done
echo ""

# Step 2: Generate load
DURATION=60
CONCURRENCY=50
RPS=200
echo "Step 2: Generating load for ${DURATION}s (${CONCURRENCY} concurrent, ~${RPS} req/s)..."
echo "  Target: $DAPR_API/catalog-service/method/products"
echo ""
echo "  Starting load test in background..."
hey -z ${DURATION}s -c $CONCURRENCY -q $(( RPS / CONCURRENCY )) \
    "$DAPR_API/catalog-service/method/products" > /tmp/hey-results.txt 2>&1 &
HEY_PID=$!

# Step 3: Monitor scaling
echo "Step 3: Monitoring HPA scaling (checking every 15s)..."
echo ""
for i in $(seq 1 8); do
    sleep 15
    echo "  [$(date +%H:%M:%S)] HPA status:"
    kubectl get hpa -n dapr-demo --no-headers 2>/dev/null | while read line; do echo "    $line"; done
    PODS=$(kubectl get pods -n dapr-demo -l app=catalog-service --no-headers 2>/dev/null | wc -l)
    echo "    catalog-service pods: $PODS"
    echo ""
done

# Wait for hey to finish
wait $HEY_PID 2>/dev/null || true

# Step 4: Show results
echo "Step 4: Load test results"
echo ""
cat /tmp/hey-results.txt 2>/dev/null || echo "  (results file not found)"
rm -f /tmp/hey-results.txt
echo ""

# Step 5: Final state
echo "Step 5: Final pod counts"
echo ""
echo "  Pods:"
kubectl get pods -n dapr-demo -l app=catalog-service --no-headers 2>/dev/null | while read line; do echo "    $line"; done
echo ""
echo "  HPA:"
kubectl get hpa -n dapr-demo --no-headers 2>/dev/null | while read line; do echo "    $line"; done
echo ""

echo "========================================="
echo "Demo Complete!"
echo "========================================="
echo ""
echo "What happened:"
echo "  1. Baseline: 1 catalog-service pod"
echo "  2. Load test: ${CONCURRENCY} concurrent connections for ${DURATION}s"
echo "  3. CPU exceeded 70% target -> HPA scaled up pods"
echo "  4. Load distributed across multiple pods"
echo "  5. After load stops, pods scale back down (~2 min stabilization)"
echo ""
echo "View in Zipkin:"
echo "  kubectl port-forward -n dapr-demo svc/zipkin 9411:9411"
echo "  http://localhost:9411"
echo "  Search for 'catalog-service' -- traces distributed across pod instances"
echo ""
echo "Watch scale-down:"
echo "  watch kubectl get hpa,pods -n dapr-demo -l app=catalog-service"
echo "========================================="
