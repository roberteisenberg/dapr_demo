#!/usr/bin/env bash
# Smoke test for APIM gateway — used by CI/CD pipeline
# Tests: catalog returns 200 (public), orders returns 401 (requires API key)
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:?Error: GATEWAY_URL environment variable is required (e.g. https://dapr-demo-apim.azure-api.net)}"

PASSED=0
FAILED=0

test_endpoint() {
    local description="$1"
    local url="$2"
    local expected_code="$3"

    echo -n "  Testing: ${description}... "
    local actual_code
    actual_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "${url}")

    if [ "${actual_code}" = "${expected_code}" ]; then
        echo "PASS (HTTP ${actual_code})"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL (expected ${expected_code}, got ${actual_code})"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== APIM Smoke Test ==="
echo "Gateway: ${GATEWAY_URL}"
echo ""

# Test 1: Catalog API is public — should return 200
test_endpoint "GET /api/v1/catalog (public, expect 200)" \
    "${GATEWAY_URL}/api/v1/catalog" \
    "200"

# Test 2: Orders API requires subscription key — should return 401 without one
test_endpoint "GET /api/v1/orders (no API key, expect 401)" \
    "${GATEWAY_URL}/api/v1/orders" \
    "401"

echo ""
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
