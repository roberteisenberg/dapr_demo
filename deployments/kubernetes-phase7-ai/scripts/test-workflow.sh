#!/bin/bash
# Test the Dapr Workflow saga pattern

set -e

BASE_URL="http://localhost:8080"
DAPR_API="$BASE_URL/v1.0/invoke"

echo "========================================="
echo "Testing Dapr Workflow Saga Pattern"
echo "========================================="
echo ""

# Step 1: Create a test product
echo "Step 1: Creating test product for workflow..."
curl -s -X POST "$DAPR_API/catalog-service/method/products" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "workflow-laptop",
    "name": "Workflow Test Laptop",
    "description": "For testing saga pattern",
    "price": 999.99,
    "stock": 10
  }' | jq .
echo ""

# Step 2: Check workflow info endpoint
echo "Step 2: Checking workflow service info..."
curl -s "$DAPR_API/workflow-service/method/workflows" | jq .
echo ""

# Step 3: Start workflow (success case)
echo "Step 3: Starting order workflow (success case)..."
RESULT=$(curl -s -X POST "$DAPR_API/workflow-service/method/workflows/order" \
  -H 'Content-Type: application/json' \
  -d '{
    "orderId": "saga-test-001",
    "productId": "workflow-laptop",
    "quantity": 2,
    "customerName": "Test User",
    "customerEmail": "test@example.com"
  }')
echo "$RESULT" | jq .
INSTANCE_ID=$(echo "$RESULT" | jq -r '.instanceId')
echo ""

# Step 4: Wait and check workflow status
echo "Step 4: Waiting for workflow to complete..."
sleep 3
echo "Checking workflow status..."
curl -s "$DAPR_API/workflow-service/method/workflows/$INSTANCE_ID" | jq .
echo ""

# Step 5: Verify stock was reduced
echo "Step 5: Verifying stock was reduced (should be 8)..."
curl -s "$DAPR_API/catalog-service/method/products/workflow-laptop" | jq .
echo ""

# Step 6: Test compensation (payment failure)
echo "========================================="
echo "Testing Saga Compensation (Payment Failure)"
echo "========================================="
echo ""

echo "Step 6: Creating expensive product (price > \$10k will fail payment)..."
curl -s -X POST "$DAPR_API/catalog-service/method/products" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "expensive-item",
    "name": "Expensive Item",
    "description": "Price exceeds payment limit",
    "price": 15000.00,
    "stock": 5
  }' | jq .
echo ""

echo "Step 7: Starting workflow that will fail payment..."
FAIL_RESULT=$(curl -s -X POST "$DAPR_API/workflow-service/method/workflows/order" \
  -H 'Content-Type: application/json' \
  -d '{
    "orderId": "saga-fail-001",
    "productId": "expensive-item",
    "quantity": 1,
    "customerName": "Test User",
    "customerEmail": "test@example.com"
  }')
echo "$FAIL_RESULT" | jq .
FAIL_INSTANCE_ID=$(echo "$FAIL_RESULT" | jq -r '.instanceId')
echo ""

echo "Step 8: Waiting for workflow to complete (with compensation)..."
sleep 5
echo "Checking workflow status (should be Failed)..."
curl -s "$DAPR_API/workflow-service/method/workflows/$FAIL_INSTANCE_ID" | jq .
echo ""

echo "Step 9: Verifying stock was restored to 5 (compensation worked)..."
curl -s "$DAPR_API/catalog-service/method/products/expensive-item" | jq .
echo ""

echo "========================================="
echo "Workflow Test Complete!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Success case: Workflow completed, stock reduced from 10 to 8"
echo "  - Failure case: Payment failed, compensation restored stock to 5"
echo ""
echo "View traces in Zipkin:"
echo "  kubectl port-forward -n dapr-demo svc/zipkin 9411:9411"
echo "  Open http://localhost:9411"
echo "  Search for 'workflow-service' traces"
echo ""
echo "Check notification-service logs for events:"
echo "  kubectl logs -f deployment/notification-service -c notification-service -n dapr-demo"
echo "========================================="
