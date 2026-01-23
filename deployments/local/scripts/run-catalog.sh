#!/bin/bash

# Phase 1: Run Catalog Service on host with Dapr sidecar
echo "Starting Catalog Service with Dapr (Host-Based)..."
echo ""
echo "Prerequisites:"
echo "  ✓ Dapr CLI installed (dapr init completed)"
echo "  ✓ Go installed"
echo "  ✓ Redis running (from dapr init)"
echo ""
echo "Service will be available at:"
echo "  - App:        http://localhost:8080"
echo "  - Dapr HTTP:  http://localhost:3500"
echo "  - Dapr gRPC:  localhost:50001"
echo ""

# Get the absolute path to components directory
COMPONENTS_PATH="$(cd "$(dirname "$0")/../components" && pwd)"
SERVICE_PATH="$(cd "$(dirname "$0")/../catalog-service" && pwd)"

# Change to service directory
cd "$SERVICE_PATH"

# Run the service with Dapr
dapr run \
  --app-id catalog-service \
  --app-port 8080 \
  --dapr-http-port 3500 \
  --dapr-grpc-port 50001 \
  --components-path "$COMPONENTS_PATH" \
  --log-level info \
  -- go run main.go

echo ""
echo "Catalog Service stopped"
