#!/bin/bash

echo "Testing Local Dapr Deployment"
echo "=============================="
echo ""

# Check if jq is available
if command -v jq &> /dev/null; then
    FORMAT="jq"
else
    FORMAT="cat"
fi

echo "Step 1: Create a product in Catalog Service"
echo "--------------------------------------------"
curl -s -X POST http://localhost:8080/products \
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

echo "Step 2: Create an order via Order Service"
echo "------------------------------------------"
echo "(This will call Catalog Service to check stock, then publish an event)"
echo ""
curl -s -X POST http://localhost:8081/orders \
  -H "Content-Type: application/json" \
  -d '{
    "orderId": "order-001",
    "productId": "gaming-laptop",
    "quantity": 2
  }' | $FORMAT
echo ""
echo ""

echo "Step 3: Wait for Notification Service to receive the event..."
echo "--------------------------------------------------------------"
echo "(Check the notification-service terminal - you should see a notification!)"
echo ""
sleep 2

echo "Step 4: Verify order was saved"
echo "-------------------------------"
curl -s http://localhost:8081/orders/order-001 | $FORMAT
echo ""
echo ""

echo "Test Complete!"
echo ""
echo "What just happened:"
echo "1. Product created in Catalog Service (Dapr State)"
echo "2. Order Service called Catalog via Dapr Service Invocation"
echo "3. Order Service published event via Dapr Pub/Sub"
echo "4. Notification Service received event via Dapr Pub/Sub"
echo "5. Order saved to state store via Dapr State Management"
echo ""
echo "All 3 Dapr building blocks demonstrated!"
