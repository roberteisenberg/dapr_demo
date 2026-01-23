#!/bin/bash

echo "Setting up Local Dapr services..."
echo ""

# Setup Go dependencies for Catalog Service
echo "1. Setting up Catalog Service (Go)"
echo "   Downloading dependencies..."
cd catalog-service
go mod download
cd ..
echo "   Done"
echo ""

# Setup Python dependencies for Order Service
echo "2. Setting up Order Service (Python)"
echo "   Installing pip dependencies..."
cd order-service
pip3 install -q -r requirements.txt
cd ..
echo "   Done"
echo ""

# Setup Node.js dependencies for Notification Service
echo "3. Setting up Notification Service (Node.js)"
echo "   Installing npm dependencies..."
cd notification-service
npm install --silent
cd ..
echo "   Done"
echo ""

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "To run all services:"
echo "  dapr run -f ."
echo ""
echo "To test:"
echo "  ./scripts/test-local.sh"
echo ""
