#!/bin/bash
# Demo: Kill a service -> circuit breaker trips -> retries succeed on recovery
#
# What happens:
# 1. Verify catalog-service is healthy
# 2. Scale catalog-service to 0 (simulates crash)
# 3. Call order-service which tries to invoke catalog-service
#    -> Dapr retries with exponential backoff -> eventually circuit breaker trips
# 4. Scale catalog-service back to 1
# 5. Wait for circuit breaker to half-open -> test request succeeds -> closes
# 6. Verify normal operation resumed

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

echo "========================================="
echo "Demo: Circuit Breaker + Retry Recovery"
echo "========================================="
echo ""

# Step 1: Verify healthy
echo "Step 1: Verifying catalog-service is healthy..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DAPR_API/catalog-service/method/health" 2>/dev/null)
echo "  Status: $STATUS"
if [[ "$STATUS" != "200" ]]; then
    echo "  ERROR: catalog-service is not healthy. Deploy first."
    exit 1
fi
echo ""

# Seed a test product
echo "  Seeding test product..."
curl -s -X POST "$DAPR_API/catalog-service/method/products" \
  -H 'Content-Type: application/json' \
  -d '{"id":"cb-test","name":"Circuit Breaker Test","price":50.00,"stock":100}' > /dev/null 2>&1
echo "  Done."
echo ""

# Step 2: Kill catalog-service
echo "Step 2: Killing catalog-service (scale to 0)..."
kubectl scale deployment catalog-service -n dapr-demo --replicas=0
kubectl wait --for=delete pod -l app=catalog-service -n dapr-demo --timeout=30s 2>/dev/null || true
echo "  catalog-service is DOWN"
echo ""

# Step 3: Try to use order-service (which calls catalog-service)
echo "Step 3: Calling order-service -> catalog-service (should fail with retries)..."
echo "  Watch Dapr retry with exponential backoff, then circuit breaker trips."
echo "  (This will take ~15-30 seconds due to retries)"
echo ""
START=$(date +%s)
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$DAPR_API/order-service/method/orders" \
  -H 'Content-Type: application/json' \
  -d '{"orderId":"cb-order-001","productId":"cb-test","quantity":1}' 2>/dev/null)
END=$(date +%s)
DURATION=$((END - START))
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")
echo "  Response (after ${DURATION}s): HTTP $HTTP_CODE"
echo "  Body: $BODY"
echo ""

# Step 4: Bring catalog-service back
echo "Step 4: Recovering catalog-service (scale to 1)..."
kubectl scale deployment catalog-service -n dapr-demo --replicas=1
echo "  Waiting for catalog-service to be ready..."
kubectl rollout status deployment/catalog-service -n dapr-demo --timeout=120s
echo "  catalog-service is UP"
echo ""

# Step 5: Wait for circuit breaker to half-open
echo "Step 5: Waiting for circuit breaker to half-open (30s cooldown)..."
sleep 35
echo ""

# Step 6: Verify recovery
echo "Step 6: Testing recovery..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DAPR_API/catalog-service/method/health" 2>/dev/null)
echo "  Direct health check: HTTP $STATUS"

RESPONSE=$(curl -s -X POST "$DAPR_API/order-service/method/orders" \
  -H 'Content-Type: application/json' \
  -d '{"orderId":"cb-order-002","productId":"cb-test","quantity":1}' 2>/dev/null)
echo "  Order through service invocation: $RESPONSE"
echo ""

echo "========================================="
echo "Demo Complete!"
echo "========================================="
echo ""
echo "What happened:"
echo "  1. catalog-service was killed (scaled to 0)"
echo "  2. Dapr retried calls with exponential backoff (1s, 2s, 4s, 8s, 10s)"
echo "  3. After 3 consecutive failures, the circuit breaker TRIPPED (open)"
echo "  4. While open, requests failed immediately (no more retries)"
echo "  5. catalog-service recovered"
echo "  6. After 30s, circuit breaker went half-open -> test succeeded -> closed"
echo ""
echo "View the traces in Zipkin:"
echo "  kubectl port-forward -n dapr-demo svc/zipkin 9411:9411"
echo "  http://localhost:9411 -> search for 'order-service' traces"
echo "  You'll see retry spans and failed spans during the outage."
echo "========================================="
