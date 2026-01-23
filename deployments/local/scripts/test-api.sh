#!/bin/bash

echo "Testing Catalog Service API..."
echo ""

# Check if jq is available for pretty printing
if command -v jq &> /dev/null; then
    FORMAT="jq"
    echo "ℹ️  Using jq for pretty JSON formatting"
else
    FORMAT="cat"
    echo "ℹ️  jq not installed - showing raw JSON (install with: sudo apt-get install jq)"
fi
echo ""

# Health check
echo "1. Health Check:"
curl -s http://localhost:8080/health | $FORMAT
echo ""

# Create a product
echo "2. Create Product (ID: prod-001):"
curl -s -X POST http://localhost:8080/products \
  -H "Content-Type: application/json" \
  -d '{
    "id": "prod-001",
    "name": "Laptop",
    "description": "High-performance laptop",
    "price": 999.99,
    "stock": 50
  }' | $FORMAT
echo ""

# Get the product
echo "3. Get Product (ID: prod-001):"
curl -s http://localhost:8080/products/prod-001 | $FORMAT
echo ""

# Update the product
echo "4. Update Product (ID: prod-001):"
curl -s -X PUT http://localhost:8080/products/prod-001 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Gaming Laptop",
    "description": "High-performance gaming laptop",
    "price": 1299.99,
    "stock": 30
  }' | $FORMAT
echo ""

# Get updated product
echo "5. Get Updated Product (ID: prod-001):"
curl -s http://localhost:8080/products/prod-001 | $FORMAT
echo ""

# Delete product
echo "6. Delete Product (ID: prod-001):"
curl -s -X DELETE http://localhost:8080/products/prod-001
echo "Product deleted"
echo ""

# Try to get deleted product
echo "7. Try to Get Deleted Product (should return 404):"
curl -s http://localhost:8080/products/prod-001
echo ""

echo "Testing complete!"
