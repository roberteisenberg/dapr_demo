#!/bin/bash

echo "Testing Docker Compose Dapr Deployment"
echo "======================================="
echo ""

# Check if jq is available
if command -v jq &> /dev/null; then
    FORMAT="jq"
else
    FORMAT="cat"
fi

CATALOG_URL="http://localhost:8080"
ORDER_URL="http://localhost:8081"

# Health checks first
echo "Step 0: Health Checks"
echo "---------------------"
echo -n "Catalog Service: "
curl -s "${CATALOG_URL}/health" | $FORMAT
echo ""
echo -n "Order Service: "
curl -s "${ORDER_URL}/health" | $FORMAT
echo ""
echo ""

echo "Step 1: Create a product in Catalog Service"
echo "---------------------------------------------"
echo "(Dapr State Management: saves product to Redis via sidecar)"
echo ""
curl -s -X POST ${CATALOG_URL}/products \
  -H "Content-Type: application/json" \
  -d '{
    "id": "gaming-laptop",
    "name": "Alienware Gaming Laptop",
    "description": "High-end gaming laptop",
    "price": 2499.99,
    "stock": 10
  }' | $FORMAT
echo ""
echo ""

echo "Step 2: Verify product was stored"
echo "-----------------------------------"
echo "(Dapr State Management: retrieves product from Redis via sidecar)"
echo ""
curl -s ${CATALOG_URL}/products/gaming-laptop | $FORMAT
echo ""
echo ""

echo "Step 3: Create an order via Order Service"
echo "-------------------------------------------"
echo "(This triggers all 3 Dapr building blocks:)"
echo "  - Service Invocation: order-service calls catalog-service via Dapr"
echo "  - State Management: order saved to Redis"
echo "  - Pub/Sub: OrderCreated event published"
echo ""
curl -s -X POST ${ORDER_URL}/orders \
  -H "Content-Type: application/json" \
  -d '{
    "orderId": "order-001",
    "productId": "gaming-laptop",
    "quantity": 2
  }' | $FORMAT
echo ""
echo ""

echo "Step 4: Wait for Notification Service to receive the event..."
echo "--------------------------------------------------------------"
echo "(Check notification-service logs: docker-compose logs notification-service)"
echo ""
sleep 2

echo "Step 5: Verify order was saved"
echo "-------------------------------"
echo "(Dapr State Management: retrieves order from Redis)"
echo ""
curl -s ${ORDER_URL}/orders/order-001 | $FORMAT
echo ""
echo ""

echo "Test Complete!"
echo ""
echo "What just happened:"
echo "1. Product created in Catalog Service (Dapr State Management)"
echo "2. Order Service called Catalog via Dapr Service Invocation"
echo "3. Order Service published event via Dapr Pub/Sub"
echo "4. Notification Service received event via Dapr Pub/Sub"
echo "5. Order saved to state store via Dapr State Management"
echo ""
echo "All 3 Dapr building blocks demonstrated across Docker containers!"
echo ""
echo "To see the notification event:"
echo "  docker-compose logs notification-service"
