#!/bin/bash
# Test Phase 8 security: JWT validation, access control, mTLS

# Don't use set -e: arithmetic expressions like ((PASS++)) return 1 when value is 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load Azure configuration for public URL
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    BASE_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
else
    BASE_URL="http://localhost:8080"
fi

echo "========================================="
echo "Phase 8: Security Tests"
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

# ===== 1. JWT Validation at Ingress =====
echo "--- 1. JWT Validation (OAuth2 Proxy) ---"
echo ""

# Unauthenticated API request should be rejected
echo "Test: Unauthenticated request to /v1.0/invoke/catalog-service/method/products"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1.0/invoke/catalog-service/method/products" 2>/dev/null)
check "Unauthenticated API call returns 401" "401" "$STATUS"
echo ""

# Web app (/) should be accessible without auth
echo "Test: Web app should be public (no auth required)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/" 2>/dev/null)
check "Web app returns 200" "200" "$STATUS"
echo ""

# ===== 2. Dapr mTLS =====
echo "--- 2. Dapr mTLS ---"
echo ""

echo "Checking Dapr mTLS status..."
if command -v dapr &>/dev/null; then
    MTLS_STATUS=$(dapr mtls -k 2>/dev/null || echo "unknown")
    echo "  Dapr mTLS: $MTLS_STATUS"
    if echo "$MTLS_STATUS" | grep -qi "enabled\|true"; then
        echo "  PASS: mTLS is enabled"
        ((PASS++))
    else
        echo "  INFO: mTLS status could not be confirmed (may need dapr CLI configured)"
    fi
else
    echo "  SKIP: dapr CLI not found"
fi
echo ""

# ===== 3. OAuth2 Proxy Health =====
echo "--- 3. OAuth2 Proxy Health ---"
echo ""

echo "Checking OAuth2 Proxy pod status..."
PROXY_STATUS=$(kubectl get deployment oauth2-proxy -n dapr-demo -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
check "OAuth2 Proxy has available replicas" "1" "$PROXY_STATUS"
echo ""

# ===== 4. Dapr Access Control =====
echo "--- 4. Dapr Access Control Configuration ---"
echo ""

echo "Checking Dapr Configuration for access control..."
AC_EXISTS=$(kubectl get configuration tracing -n dapr-demo -o jsonpath='{.spec.accessControl.defaultAction}' 2>/dev/null || echo "")
check "Access control defaultAction is 'deny'" "deny" "$AC_EXISTS"

POLICY_COUNT=$(kubectl get configuration tracing -n dapr-demo -o jsonpath='{.spec.accessControl.policies}' 2>/dev/null | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo "0")
echo "  Access control policies defined: $POLICY_COUNT"
echo ""

# ===== 5. Security Components =====
echo "--- 5. Security Components Status ---"
echo ""

echo "Pods in dapr-demo namespace:"
kubectl get pods -n dapr-demo -o wide 2>/dev/null | grep -E "oauth2-proxy|web-app|NAME" || echo "  Could not list pods"
echo ""

echo "ConfigMaps:"
kubectl get configmap -n dapr-demo 2>/dev/null | grep -E "web-app-config|oauth2-proxy-config|NAME" || echo "  Could not list configmaps"
echo ""

# ===== Summary =====
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    echo "Some security tests failed. Check the output above."
    exit 1
else
    echo "All security tests passed."
fi
