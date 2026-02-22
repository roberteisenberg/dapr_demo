#!/bin/bash
# Demo: Publish a poison message -> dead letter topic catches it

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
echo "Demo: Pub/Sub Dead Letter Topic"
echo "========================================="
echo ""

# Step 1: Check current dead letters
echo "Step 1: Current dead letter count..."
DL_RESPONSE=$(curl -s "$DAPR_API/notification-service/method/dead-letters" 2>/dev/null)
DL_BEFORE=$(echo "$DL_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
echo "  Dead letters: $DL_BEFORE"
echo ""

# Step 2: Send a normal order event (should succeed)
echo "Step 2: Publishing a normal order event..."
echo "  (Notification service should process this successfully)"
kubectl exec deployment/order-service -c daprd -n dapr-demo -- \
    wget -q -O- --post-data='{"orderId":"dl-normal-001","productName":"Normal Product","quantity":1,"total":25.00,"status":"created"}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/publish/pubsub/orders' 2>/dev/null || true
echo "  Published. Waiting 3 seconds..."
sleep 3

echo "  Notification service logs (last 5 lines):"
kubectl logs deployment/notification-service -c notification-service -n dapr-demo --tail=5 2>/dev/null | while read line; do echo "    $line"; done
echo ""

# Step 3: Send a poison message
echo "Step 3: Publishing a POISON message..."
echo "  (Notification service will return DROP -> Dapr routes to dead letter topic)"
kubectl exec deployment/order-service -c daprd -n dapr-demo -- \
    wget -q -O- --post-data='{"orderId":"dl-poison-001","poison":true,"productName":"Poison Product","quantity":1}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/publish/pubsub/orders' 2>/dev/null || true
echo "  Published. Waiting 5 seconds for dead letter processing..."
sleep 5
echo ""

# Step 4: Check dead letters
echo "Step 4: Checking dead letter store..."
DL_RESPONSE=$(curl -s "$DAPR_API/notification-service/method/dead-letters" 2>/dev/null)
DL_AFTER=$(echo "$DL_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
echo "  Dead letters: $DL_AFTER (was $DL_BEFORE)"
echo ""
echo "  Dead letter contents:"
echo "$DL_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "  $DL_RESPONSE"
echo ""

# Step 5: Check logs
echo "Step 5: Notification service logs (last 15 lines)..."
kubectl logs deployment/notification-service -c notification-service -n dapr-demo --tail=15 2>/dev/null | while read line; do echo "    $line"; done
echo ""

echo "========================================="
echo "Demo Complete!"
echo "========================================="
echo ""
echo "What happened:"
echo "  1. Normal message -> notification-service processed it (SUCCESS)"
echo "  2. Poison message -> notification-service returned DROP"
echo "  3. Dapr routed the dropped message to the 'orders-deadletter' topic"
echo "  4. notification-service received it on /orders-deadletter and stored it"
echo "  5. The /dead-letters endpoint shows all captured dead letters"
echo ""
echo "The message was NOT lost -- it was captured for inspection and potential replay."
echo "========================================="
