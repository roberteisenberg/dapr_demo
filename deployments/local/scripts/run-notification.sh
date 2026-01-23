#!/bin/bash

# Phase 2: Run Notification Service on host with Dapr sidecar
echo "Starting Notification Service with Dapr (Host-Based)..."
echo ""
echo "Prerequisites:"
echo "  ✓ Dapr CLI installed"
echo "  ✓ Node.js installed"
echo "  ✓ Redis running (from dapr init)"
echo ""
echo "Service will be available at:"
echo "  - App:        http://localhost:8082"
echo "  - Dapr HTTP:  http://localhost:3502"
echo "  - Dapr gRPC:  localhost:50003"
echo ""

# Get the absolute path to components directory
COMPONENTS_PATH="$(cd "$(dirname "$0")/../components" && pwd)"
SERVICE_PATH="$(cd "$(dirname "$0")/../notification-service" && pwd)"

# Change to service directory
cd "$SERVICE_PATH"

# Install npm dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing Node.js dependencies..."
    npm install
    echo ""
fi

echo "Starting Notification Service..."
echo ""

# Run the service with Dapr
dapr run \
  --app-id notification-service \
  --app-port 8082 \
  --dapr-http-port 3502 \
  --dapr-grpc-port 50003 \
  --resources-path "$COMPONENTS_PATH" \
  --log-level info \
  -- node index.js

echo ""
echo "Notification Service stopped"
