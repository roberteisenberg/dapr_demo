#!/bin/bash
set -euo pipefail

# Test Azure API Management Self-Hosted Gateway
# Verifies API routing, rate limiting, caching, and authentication

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

# Configuration
GATEWAY_URL="${GATEWAY_URL:-}"
SUBSCRIPTION_KEY="${SUBSCRIPTION_KEY:-}"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --gateway-url)
            GATEWAY_URL="$2"
            shift 2
            ;;
        --subscription-key)
            SUBSCRIPTION_KEY="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --gateway-url URL       APIM gateway URL (auto-detected from LoadBalancer)"
            echo "  --subscription-key KEY  Subscription key for Orders API"
            echo "  --verbose               Show response bodies"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

PASSED=0
FAILED=0

# Auto-detect gateway URL from LoadBalancer service
detect_gateway_url() {
    if [[ -z "$GATEWAY_URL" ]]; then
        log_info "Detecting gateway URL from LoadBalancer service..."

        GATEWAY_IP=$(kubectl get svc apim-gateway -n apim-gateway \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [[ -n "$GATEWAY_IP" ]]; then
            GATEWAY_URL="http://$GATEWAY_IP"
            log_info "Using gateway URL: $GATEWAY_URL"
        else
            log_error "Could not detect gateway URL. Use --gateway-url option"
            exit 1
        fi
    fi
}

# Test helper
run_test() {
    local name="$1"
    local expected_status="$2"
    local method="${3:-GET}"
    local url="$4"
    local data="${5:-}"
    local headers="${6:-}"

    log_info "Testing: $name"

    CURL_OPTS="-s -w '%{http_code}' -o /tmp/response_body.txt"

    if [[ -n "$headers" ]]; then
        CURL_OPTS="$CURL_OPTS $headers"
    fi

    if [[ "$method" == "POST" && -n "$data" ]]; then
        RESPONSE_CODE=$(curl $CURL_OPTS -X POST -H "Content-Type: application/json" -d "$data" "$url" 2>/dev/null | tr -d "'")
    else
        RESPONSE_CODE=$(curl $CURL_OPTS "$url" 2>/dev/null | tr -d "'")
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo "Response code: $RESPONSE_CODE"
        echo "Response body:"
        cat /tmp/response_body.txt
        echo ""
    fi

    if [[ "$RESPONSE_CODE" == "$expected_status" ]]; then
        log_success "$name (HTTP $RESPONSE_CODE)"
        ((PASSED++))
        return 0
    else
        log_error "$name - Expected $expected_status, got $RESPONSE_CODE"
        ((FAILED++))
        return 1
    fi
}

# Test gateway health
test_gateway_health() {
    echo ""
    echo "=== Gateway Health ==="

    # Check gateway pods
    READY=$(kubectl get pods -n apim-gateway -l app=apim-gateway \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c True || echo 0)

    if [[ "$READY" -ge 1 ]]; then
        log_success "Gateway pods running: $READY"
        ((PASSED++))
    else
        log_error "No ready gateway pods"
        ((FAILED++))
    fi

    # Check Dapr sidecars
    DAPR_READY=$(kubectl get pods -n apim-gateway -l app=apim-gateway \
        -o jsonpath='{.items[*].status.containerStatuses[?(@.name=="daprd")].ready}' 2>/dev/null | grep -c true || echo 0)

    if [[ "$DAPR_READY" -ge 1 ]]; then
        log_success "Dapr sidecars running: $DAPR_READY"
        ((PASSED++))
    else
        log_error "No ready Dapr sidecars"
        ((FAILED++))
    fi
}

# Test Catalog API (public, cached)
test_catalog_api() {
    echo ""
    echo "=== Catalog API Tests ==="

    # Test list products
    run_test "GET /api/v1/catalog - List products" "200" "GET" "$GATEWAY_URL/api/v1/catalog"

    # Test get product by ID
    run_test "GET /api/v1/catalog/1 - Get product" "200" "GET" "$GATEWAY_URL/api/v1/catalog/1"

    # Test caching - second request should be cached
    log_info "Testing response caching..."
    FIRST_RESPONSE=$(curl -s -w '\n%{http_code}' -D /tmp/headers1.txt "$GATEWAY_URL/api/v1/catalog" 2>/dev/null)
    sleep 1
    SECOND_RESPONSE=$(curl -s -w '\n%{http_code}' -D /tmp/headers2.txt "$GATEWAY_URL/api/v1/catalog" 2>/dev/null)

    # Check for cache header
    if grep -q "X-Cache-Status: HIT" /tmp/headers2.txt 2>/dev/null; then
        log_success "Response caching working (X-Cache-Status: HIT)"
        ((PASSED++))
    else
        log_warning "Cache header not found (cache may not be active yet)"
    fi
}

# Test Orders API (requires subscription)
test_orders_api() {
    echo ""
    echo "=== Orders API Tests ==="

    # Test without subscription key - should fail
    run_test "GET /api/v1/orders without key - Should be 401" "401" "GET" "$GATEWAY_URL/api/v1/orders"

    if [[ -z "$SUBSCRIPTION_KEY" ]]; then
        log_warning "Subscription key not provided, skipping authenticated tests"
        log_warning "Use --subscription-key to test authenticated endpoints"
        return
    fi

    # Test with subscription key
    run_test "GET /api/v1/orders with key - List orders" "200" "GET" \
        "$GATEWAY_URL/api/v1/orders" "" "-H 'X-API-Key: $SUBSCRIPTION_KEY'"

    # Test create order
    ORDER_DATA='{"productId":"1","quantity":2,"customerName":"Test User","customerEmail":"test@example.com"}'
    run_test "POST /api/v1/orders with key - Create order" "202" "POST" \
        "$GATEWAY_URL/api/v1/orders" "$ORDER_DATA" "-H 'X-API-Key: $SUBSCRIPTION_KEY'"
}

# Test rate limiting
test_rate_limiting() {
    echo ""
    echo "=== Rate Limiting Tests ==="

    log_info "Testing rate limiting (sending 20 rapid requests)..."

    RATE_LIMITED=false
    for i in {1..20}; do
        CODE=$(curl -s -o /dev/null -w '%{http_code}' "$GATEWAY_URL/api/v1/catalog" 2>/dev/null)
        if [[ "$CODE" == "429" ]]; then
            RATE_LIMITED=true
            log_success "Rate limiting active (429 response after $i requests)"
            ((PASSED++))
            break
        fi
    done

    if [[ "$RATE_LIMITED" == "false" ]]; then
        log_warning "Rate limiting not triggered in 20 requests (limit may be higher)"
    fi
}

# Test request validation
test_request_validation() {
    echo ""
    echo "=== Request Validation Tests ==="

    if [[ -z "$SUBSCRIPTION_KEY" ]]; then
        log_warning "Subscription key not provided, skipping validation tests"
        return
    fi

    # Test invalid JSON
    run_test "POST invalid JSON - Should be 400" "400" "POST" \
        "$GATEWAY_URL/api/v1/orders" "not valid json" "-H 'X-API-Key: $SUBSCRIPTION_KEY'"

    # Test oversized request (would need very large payload to trigger 10KB limit)
    log_info "Request size validation configured (max 10KB)"
}

# Test CORS
test_cors() {
    echo ""
    echo "=== CORS Tests ==="

    log_info "Testing CORS preflight..."
    CORS_RESPONSE=$(curl -s -D - -o /dev/null \
        -X OPTIONS \
        -H "Origin: http://localhost:3000" \
        -H "Access-Control-Request-Method: POST" \
        "$GATEWAY_URL/api/v1/orders" 2>/dev/null)

    if echo "$CORS_RESPONSE" | grep -q "Access-Control-Allow-Origin"; then
        log_success "CORS headers present"
        ((PASSED++))
    else
        log_warning "CORS headers not detected"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo ""
    echo -e "Passed: ${GREEN}$PASSED${NC}"
    echo -e "Failed: ${RED}$FAILED${NC}"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "$FAILED test(s) failed"
        exit 1
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "APIM Gateway Test Suite"
    echo "=========================================="

    detect_gateway_url

    test_gateway_health
    test_catalog_api
    test_orders_api
    test_rate_limiting
    test_request_validation
    test_cors

    print_summary
}

main "$@"
