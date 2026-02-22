#!/bin/bash
# Demo: Concurrent stock reservations showing turn-based actor concurrency.
#
# Without actors: two concurrent "reserve 8 of 10" requests could both read stock=10,
# both succeed, and stock goes to -6 (race condition).
#
# With actors: the ProductActor processes requests one at a time (turn-based).
# First request reserves 8, stock=2. Second request sees stock=2, fails.

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
echo "Demo: Actor Concurrency (No Race Conditions)"
echo "========================================="
echo ""

# Step 1: Create a product with limited stock
echo "Step 1: Creating product with 10 units of stock..."
curl -s -X POST "$DAPR_API/catalog-service/method/products" \
    -H 'Content-Type: application/json' \
    -d '{"id":"concurrency-test","name":"Limited Widget","price":50.00,"stock":10}' > /dev/null 2>&1
sleep 2
echo "  Done. Stock: 10"
echo ""

# Step 2: Verify actor stock
echo "Step 2: Verifying actor stock..."
STOCK=$(kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- --method=PUT --body-data='{}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/actors/ProductActorType/concurrency-test/method/GetStock' 2>/dev/null)
echo "  Actor stock: $STOCK"
echo ""

# Step 3: Fire two concurrent reservations for 8 units each
echo "Step 3: Firing TWO concurrent reservations for 8 units each..."
echo "  (Only one should succeed — stock is 10, not 16)"
echo ""

# Run both in background and capture results
kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- --method=PUT --body-data='{"quantity":8}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/actors/ProductActorType/concurrency-test/method/Reserve' \
    > /tmp/actor-reserve-1.json 2>/dev/null &
PID1=$!

kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- --method=PUT --body-data='{"quantity":8}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/actors/ProductActorType/concurrency-test/method/Reserve' \
    > /tmp/actor-reserve-2.json 2>/dev/null &
PID2=$!

wait $PID1 $PID2 2>/dev/null || true

echo "  Reservation 1 result:"
cat /tmp/actor-reserve-1.json 2>/dev/null | python3 -m json.tool 2>/dev/null || cat /tmp/actor-reserve-1.json 2>/dev/null
echo ""

echo "  Reservation 2 result:"
cat /tmp/actor-reserve-2.json 2>/dev/null | python3 -m json.tool 2>/dev/null || cat /tmp/actor-reserve-2.json 2>/dev/null
echo ""

# Step 4: Check final stock
echo "Step 4: Final actor stock..."
FINAL_STOCK=$(kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- --method=PUT --body-data='{}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/actors/ProductActorType/concurrency-test/method/GetStock' 2>/dev/null)
echo "  $FINAL_STOCK"
echo ""

# Step 5: Release and clean up
echo "Step 5: Releasing reserved stock and cleaning up..."
kubectl exec deployment/catalog-service -c daprd -n dapr-demo -- \
    wget -q -O- --method=PUT --body-data='{"quantity":8}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/actors/ProductActorType/concurrency-test/method/Release' > /dev/null 2>/dev/null || true
curl -s -X DELETE "$DAPR_API/catalog-service/method/products/concurrency-test" > /dev/null 2>&1
rm -f /tmp/actor-reserve-1.json /tmp/actor-reserve-2.json
echo "  Done."
echo ""

echo "========================================="
echo "Demo Complete!"
echo "========================================="
echo ""
echo "What happened:"
echo "  1. Created a product with 10 units of stock"
echo "  2. Fired TWO concurrent requests to reserve 8 units each"
echo "  3. The actor processed them one at a time (turn-based concurrency)"
echo "  4. First request succeeded (stock: 10 -> 2)"
echo "  5. Second request failed: insufficient stock (available=2, requested=8)"
echo "  6. Stock never went negative — no race condition!"
echo ""
echo "Without actors, both requests could read stock=10 simultaneously,"
echo "both decrement to 2, and the product would be oversold."
echo ""
echo "View in Zipkin:"
echo "  kubectl port-forward -n dapr-demo svc/zipkin 9411:9411"
echo "  http://localhost:9411"
echo "  Search for 'catalog-service' — see actor invocations in traces"
echo "========================================="
