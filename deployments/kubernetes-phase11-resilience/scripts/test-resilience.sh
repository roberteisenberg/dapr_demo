#!/bin/bash
# Test Phase 11 resilience features: resiliency policy, dead letter, HPA

# Don't use set -e: arithmetic expressions like ((PASS++)) return 1 when value is 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load Azure configuration for public URL
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    BASE_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
else
    # Try parent phase configs
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
echo "Phase 11: Resilience Tests"
echo "========================================="
echo "URL: $BASE_URL"
echo ""

PASS=0
FAIL=0

check() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $desc (got $actual)"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected $expected, got $actual)"
        ((FAIL++))
    fi
}

# === 1. Resiliency Policy ===
echo "--- 1. Dapr Resiliency Policy ---"
echo ""

RESILIENCY_NAME=$(kubectl get resiliency -n dapr-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
check "Resiliency resource exists" "default-resilience" "$RESILIENCY_NAME"

# Verify scopes include all backend services
SCOPES=$(kubectl get resiliency default-resilience -n dapr-demo -o jsonpath='{.scopes}' 2>/dev/null || echo "")
for svc in catalog-service order-service notification-service workflow-service; do
    if echo "$SCOPES" | grep -q "$svc"; then
        echo "  PASS: Resiliency scoped to $svc"
        ((PASS++))
    else
        echo "  FAIL: Resiliency not scoped to $svc"
        ((FAIL++))
    fi
done
echo ""

# === 2. HPAs ===
echo "--- 2. Horizontal Pod Autoscalers ---"
echo ""

CATALOG_HPA=$(kubectl get hpa catalog-service-hpa -n dapr-demo -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
check "Catalog HPA exists" "catalog-service-hpa" "$CATALOG_HPA"

ORDER_HPA=$(kubectl get hpa order-service-hpa -n dapr-demo -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
check "Order HPA exists" "order-service-hpa" "$ORDER_HPA"

CATALOG_MAX=$(kubectl get hpa catalog-service-hpa -n dapr-demo -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "0")
check "Catalog HPA maxReplicas" "5" "$CATALOG_MAX"

ORDER_MAX=$(kubectl get hpa order-service-hpa -n dapr-demo -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "0")
check "Order HPA maxReplicas" "5" "$ORDER_MAX"
echo ""

# === 3. Dead Letter Topic ===
echo "--- 3. Dead Letter Topic ---"
echo ""

# Check dead letter count before
DL_BEFORE=$(curl -s "$DAPR_API/notification-service/method/dead-letters" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
echo "  Dead letters before: $DL_BEFORE"

# Publish a poison message via Dapr sidecar
echo "  Publishing poison message..."
kubectl exec deployment/order-service -c daprd -n dapr-demo -- \
    wget -q -O- --post-data='{"orderId":"poison-test","poison":true}' \
    --header='Content-Type: application/json' \
    'http://localhost:3500/v1.0/publish/pubsub/orders' 2>/dev/null || true

sleep 5

# Check dead letter count after
DL_AFTER=$(curl -s "$DAPR_API/notification-service/method/dead-letters" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
echo "  Dead letters after: $DL_AFTER"

if [[ "$DL_AFTER" -gt "$DL_BEFORE" ]]; then
    echo "  PASS: Dead letter count increased ($DL_BEFORE -> $DL_AFTER)"
    ((PASS++))
else
    echo "  FAIL: Dead letter count did not increase ($DL_BEFORE -> $DL_AFTER)"
    ((FAIL++))
fi
echo ""

# === 4. Services Healthy ===
echo "--- 4. Services Healthy with Resilience ---"
echo ""

CATALOG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DAPR_API/catalog-service/method/health" 2>/dev/null)
check "Catalog service healthy" "200" "$CATALOG_STATUS"

ORDER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DAPR_API/order-service/method/health" 2>/dev/null)
check "Order service healthy" "200" "$ORDER_STATUS"

NOTIF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DAPR_API/notification-service/method/health" 2>/dev/null)
check "Notification service healthy" "200" "$NOTIF_STATUS"
echo ""

# === Summary ===
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="

if [[ "$FAIL" -gt 0 ]]; then
    echo "Some resilience tests failed."
    exit 1
else
    echo "All resilience tests passed."
fi
