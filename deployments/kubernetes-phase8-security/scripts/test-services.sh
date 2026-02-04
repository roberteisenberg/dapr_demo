#!/bin/bash
# Test services through the Dapr API gateway (AKS public endpoint)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load Azure configuration
CONFIG_FILE="$SCRIPT_DIR/../.azure-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    BASE_URL="http://$DNS_LABEL.$LOCATION.cloudapp.azure.com"
else
    # Fall back to localhost (for port-forward testing)
    BASE_URL="http://localhost:8080"
fi

echo "Testing AKS Dapr Deployment"
echo "==================================="
echo "Endpoint: $BASE_URL"
echo ""

# Check if jq is available
if command -v jq &> /dev/null; then
    FORMAT="jq"
else
    FORMAT="cat"
fi

DAPR_API="$BASE_URL/v1.0/invoke"

# Check if endpoint is reachable
if ! curl -s --connect-timeout 5 "$BASE_URL" > /dev/null 2>&1; then
    echo "ERROR: Cannot reach $BASE_URL"
    echo ""
    echo "If testing locally, start port-forward first:"
    echo "  kubectl port-forward -n dapr-demo svc/api-gateway-ingress-nginx-controller 8080:80"
    exit 1
fi

echo "Step 0: Health Checks (via Dapr service invocation)"
echo "----------------------------------------------------"
echo -n "Catalog Service: "
curl -s "$DAPR_API/catalog-service/method/health" | $FORMAT
echo ""
echo -n "Order Service: "
curl -s "$DAPR_API/order-service/method/health" | $FORMAT
echo ""
echo ""

echo "Step 1: Create a product in Catalog Service"
echo "---------------------------------------------"
echo "(Dapr State Management: saves product via sidecar)"
echo ""
curl -s -X POST "$DAPR_API/catalog-service/method/products" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "aks-laptop",
    "name": "AKS Cloud Laptop",
    "description": "Cloud-native laptop on Azure",
    "price": 1999.99,
    "stock": 10
  }' | $FORMAT
echo ""
echo ""

echo "Step 2: Verify product was stored"
echo "-----------------------------------"
echo "(Dapr State Management: retrieves product via sidecar)"
echo ""
curl -s "$DAPR_API/catalog-service/method/products/aks-laptop" | $FORMAT
echo ""
echo ""

echo "Step 3: Create an order via Order Service"
echo "-------------------------------------------"
echo "(This triggers all 3 Dapr building blocks:)"
echo "  - Service Invocation: order-service calls catalog-service via Dapr"
echo "  - State Management: order saved"
echo "  - Pub/Sub: OrderCreated event published"
echo ""
curl -s -X POST "$DAPR_API/order-service/method/orders" \
  -H 'Content-Type: application/json' \
  -d '{
    "orderId": "aks-order-001",
    "productId": "aks-laptop",
    "quantity": 2
  }' | $FORMAT
echo ""
echo ""

echo "Step 4: Verify order was saved"
echo "-------------------------------"
echo "(Dapr State Management: retrieves order)"
echo ""
curl -s "$DAPR_API/order-service/method/orders/aks-order-001" | $FORMAT
echo ""
echo ""

echo "========================================="
echo "Test Complete!"
echo "========================================="
echo ""
echo "What just happened:"
echo "1. Product created in Catalog Service (Dapr State Management)"
echo "2. Order Service called Catalog via Dapr Service Invocation"
echo "3. Order Service published event via Dapr Pub/Sub"
echo "4. Notification Service received event via Dapr Pub/Sub"
echo "5. Order saved to state store via Dapr State Management"
echo ""
echo "All 3 Dapr building blocks demonstrated on AKS!"
echo ""
echo "Public URL: $BASE_URL"
echo ""
echo "To verify notification was received:"
echo "  kubectl logs deployment/notification-service -c notification-service -n dapr-demo"
echo ""
echo "Dashboards:"
echo "  Zipkin: kubectl port-forward -n dapr-demo svc/zipkin 9411:9411"
echo "  Dapr:   dapr dashboard -k -n dapr-demo"
echo "========================================="
