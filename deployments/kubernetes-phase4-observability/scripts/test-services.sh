#!/bin/bash
# Test services through the Dapr API gateway (ingress)

set -e

echo "Testing Kubernetes Dapr Deployment"
echo "==================================="
echo ""

# Check if jq is available
if command -v jq &> /dev/null; then
    FORMAT="jq"
else
    FORMAT="cat"
fi

BASE_URL="http://localhost:8080"
DAPR_API="$BASE_URL/v1.0/invoke"

# Check if port-forward is running
if ! curl -s "$BASE_URL" > /dev/null 2>&1; then
    echo "ERROR: Cannot reach $BASE_URL"
    echo ""
    echo "Start port-forward first:"
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
    "id": "k8s-laptop",
    "name": "Kubernetes Laptop",
    "description": "Cloud-native laptop",
    "price": 1999.99,
    "stock": 10
  }' | $FORMAT
echo ""
echo ""

echo "Step 2: Verify product was stored"
echo "-----------------------------------"
echo "(Dapr State Management: retrieves product via sidecar)"
echo ""
curl -s "$DAPR_API/catalog-service/method/products/k8s-laptop" | $FORMAT
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
    "orderId": "k8s-order-001",
    "productId": "k8s-laptop",
    "quantity": 2
  }' | $FORMAT
echo ""
echo ""

echo "Step 4: Verify order was saved"
echo "-------------------------------"
echo "(Dapr State Management: retrieves order)"
echo ""
curl -s "$DAPR_API/order-service/method/orders/k8s-order-001" | $FORMAT
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
echo "All 3 Dapr building blocks demonstrated through the API gateway!"
echo ""
echo "To verify notification was received:"
echo "  kubectl logs deployment/notification-service -c notification-service -n dapr-demo"
echo ""
echo "Dapr dashboard:"
echo "  dapr dashboard -k -n dapr-demo"
echo "========================================="
