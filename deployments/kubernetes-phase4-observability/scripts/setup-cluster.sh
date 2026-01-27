#!/bin/bash
# Setup minikube cluster, install Dapr, and configure nginx-ingress with Dapr sidecar

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Phase 3: Kubernetes Cluster Setup"
echo "========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found. Please install Docker Desktop."
    exit 1
fi
echo "  Docker: OK"

if ! command -v minikube &> /dev/null; then
    echo "ERROR: minikube not found."
    echo "  Install: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
    echo "           sudo install minikube-linux-amd64 /usr/local/bin/minikube"
    exit 1
fi
echo "  minikube: OK ($(minikube version --short))"

if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found."
    echo "  Install: curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    echo "           sudo install kubectl /usr/local/bin/kubectl"
    exit 1
fi
echo "  kubectl: OK"

if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm not found."
    echo "  Install: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi
echo "  Helm: OK ($(helm version --short))"

if ! command -v dapr &> /dev/null; then
    echo "ERROR: Dapr CLI not found."
    echo "  Install: wget -q https://raw.githubusercontent.com/dapr/cli/master/install/install.sh -O - | /bin/bash"
    exit 1
fi
echo "  Dapr CLI: OK"

echo ""

# Start minikube
echo "Starting minikube cluster..."
if minikube status | grep -q "Running"; then
    echo "  minikube already running"
else
    minikube start --driver=docker --cpus=2 --memory=4096
fi

# Wait for cluster
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo "  Cluster ready"

# Install Dapr on Kubernetes
echo ""
if kubectl get namespace dapr-system &> /dev/null; then
    echo "Dapr already installed on Kubernetes"
    dapr status -k
else
    echo "Installing Dapr on Kubernetes..."
    dapr init -k --wait --timeout 600
    echo ""
    echo "Dapr installation complete:"
    dapr status -k
fi

# Create namespace
echo ""
echo "Creating dapr-demo namespace..."
kubectl create namespace dapr-demo 2>/dev/null || echo "  Namespace already exists"

# Create tracing config (required by ingress controller's Dapr sidecar)
echo "Creating Dapr tracing configuration..."
cat <<EOF | kubectl apply -f -
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: tracing
  namespace: dapr-demo
spec:
  tracing:
    samplingRate: "1"
    zipkin:
      endpointAddress: "http://zipkin.dapr-demo.svc.cluster.local:9411/api/v2/spans"
EOF

# Install nginx-ingress with Dapr sidecar
echo ""
echo "Installing nginx-ingress with Dapr sidecar..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx

helm upgrade --install api-gateway ingress-nginx/ingress-nginx \
  --namespace dapr-demo \
  --values "$SCRIPT_DIR/../config/ingress-values.yaml" \
  --timeout 10m

# Wait for the ingress controller pod to be ready with Dapr sidecar (2/2 containers)
echo "  Waiting for ingress controller and Dapr sidecar..."
kubectl wait --for=condition=available --timeout=300s deployment/api-gateway-ingress-nginx-controller -n dapr-demo

# Verify both containers are running
while true; do
  READY=$(kubectl get pods -n dapr-demo -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null | tr ' ' '\n' | grep -c true || echo 0)
  if [ "$READY" -ge 2 ]; then
    break
  fi
  echo "  Waiting for Dapr sidecar injection... ($READY/2 containers ready)"
  sleep 5
done

echo "  nginx-ingress installed with Dapr sidecar (2/2 containers ready)"

echo ""
echo "========================================="
echo "Cluster Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. eval \$(minikube docker-env)"
echo "  2. ./scripts/build-images.sh"
echo "  3. ./scripts/deploy-all.sh"
echo ""
echo "Dashboards:"
echo "  Minikube: minikube dashboard"
echo "  Dapr:     dapr dashboard -k -n dapr-demo"
echo "========================================="
