#!/bin/bash

# Phase 2: Run Order Service on host with Dapr sidecar
echo "Starting Order Service with Dapr (Host-Based)..."
echo ""
echo "Prerequisites:"
echo "  ✓ Dapr CLI installed"
echo "  ✓ Python 3 installed"
echo "  ✓ Redis running (from dapr init)"
echo ""
echo "Service will be available at:"
echo "  - App:        http://localhost:8081"
echo "  - Dapr HTTP:  http://localhost:3501"
echo "  - Dapr gRPC:  localhost:50002"
echo ""

# Get the absolute path to components directory
COMPONENTS_PATH="$(cd "$(dirname "$0")/../components" && pwd)"
SERVICE_PATH="$(cd "$(dirname "$0")/../order-service" && pwd)"

# Change to service directory
cd "$SERVICE_PATH"

# Check if virtual environment exists, create if not
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment and install dependencies
echo "Installing Python dependencies..."
source venv/bin/activate
pip install -q -r requirements.txt

echo ""
echo "Starting Order Service..."
echo ""

# Run the service with Dapr
dapr run \
  --app-id order-service \
  --app-port 8081 \
  --dapr-http-port 3501 \
  --dapr-grpc-port 50002 \
  --resources-path "$COMPONENTS_PATH" \
  --log-level info \
  -- python3 app.py

echo ""
echo "Order Service stopped"
