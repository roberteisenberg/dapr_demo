# Phase 7/7-A: AI Integration

Deploy the Dapr microservices demo with AI capabilities. This phase introduces AI in two steps:

- **Phase 7 (Manual):** "Copy for AI" button exports data for Claude Desktop
- **Phase 7-A (Fraud Check):** AI-powered fraud detection in the order fulfillment workflow via Dapr Conversation API

See [ARCHITECTURE.md](ARCHITECTURE.md) for the updated workflow diagram.

## What's New?

| Feature | Phase | Description |
|---------|-------|-------------|
| "Copy for AI" button | 7 | Exports catalog and order data as a prompt for Claude |
| Order list endpoint | 7 | `GET /orders` returns all orders (new in order-service) |
| Fraud check activity | 7-A | `CheckFraudActivity` calls Claude to assess order risk before payment |
| Dapr Conversation API | 7-A | Provider-agnostic LLM calls (`conversation.anthropic` component) |
| Updated saga display | 7-A | Frontend shows 5-step saga: Validate → Reserve → Check Fraud → Payment → Notify |

## What You'll Learn

- Adding an AI step to an existing deterministic workflow (saga pattern)
- Dapr Conversation API — provider-agnostic LLM abstraction (Claude, OpenAI, etc.)
- API key management via Kubernetes secrets + Dapr `secretKeyRef` (app never sees the key)
- Workflow compensation when AI flags an order (inventory release)
- Feature detection pattern (frontend adapts to available services)

## Prerequisites

- Docker Desktop (running, WSL2 backend)
- minikube
- kubectl
- Helm
- Dapr CLI
- jq (for test scripts): `sudo apt-get install -y jq`
- A Claude account ([claude.ai](https://claude.ai)) or Claude Desktop app
- An Anthropic API key (for Phase 7-A)

### Coming from Phase 5 (Workflow)?

If you already have Phase 5 running, you can use the same cluster. Just rebuild and redeploy:

```bash
cd deployments/kubernetes-phase7-ai
eval $(minikube docker-env)
./scripts/build-images.sh --with-frontend
./scripts/deploy-all.sh --with-frontend
```

## Quick Start

### 1. Setup cluster (skip if already running)

**Starting fresh?** Clean up any previous setup first:

```bash
pkill -f "kubectl port-forward" 2>/dev/null || true
minikube delete
```

Then setup:

```bash
cd deployments/kubernetes-phase7-ai
./scripts/setup-cluster.sh
```

### 2. Build images

```bash
eval $(minikube docker-env)
./scripts/build-images.sh --with-frontend
```

### 3. Create API key secret (Phase 7-A)

The fraud check activity needs a Claude API key:

```bash
kubectl create secret generic anthropic-api-key \
  --from-literal=api-key=$ANTHROPIC_API_KEY \
  -n dapr-demo
```

If you skip this step, the fraud check will approve all orders by default (graceful degradation).

### 4. Deploy services

```bash
./scripts/deploy-all.sh --with-frontend
```

### 5. Start port-forward

```bash
kubectl port-forward -n dapr-demo svc/api-gateway-ingress-nginx-controller 8080:80 &
```

### 6. Access the application

Open http://localhost:8080

## Fraud Check in Action

1. **Add products** — Create several products in the catalog
2. **Place a workflow order** — Click "Order (Workflow)" on any product
3. **Watch the saga** — The 5-step progress display shows:
   - Validate Order → Reserve Inventory → **Check Fraud** → Process Payment → Send Notification
4. **Check logs** — See Claude's fraud assessment:

```bash
kubectl logs -f deployment/workflow-service -c workflow-service -n dapr-demo
```

If Claude flags an order as high risk, the workflow compensates (releases inventory) and reports the fraud reasoning in the UI.

## "Copy for AI" (Phase 7 — Manual)

1. **Add products** and **place orders** to build up history
2. **Click "Copy for AI"** — Formats data as a prompt, copies to clipboard
3. **Paste into Claude** — Open [claude.ai](https://claude.ai) or Claude Desktop
4. **Get recommendations** — Claude suggests new products to stock

## Testing

```bash
# Run service tests
./scripts/test-services.sh

# Test the order list endpoint directly
curl -s http://localhost:8080/v1.0/invoke/order-service/method/orders | jq

# Test workflow with fraud check
./scripts/test-workflow.sh
```

## Phase 3-A/3-B: Infrastructure Swaps

These still work:

```bash
./scripts/deploy-all.sh --with-frontend --pubsub rabbitmq
./scripts/deploy-all.sh --with-frontend --statestore mongodb
```

## Dashboards

| Dashboard | Command | URL |
|-----------|---------|-----|
| Zipkin | `kubectl port-forward -n dapr-demo svc/zipkin 9411:9411` | http://localhost:9411 |
| Dapr | `dapr dashboard -k -n dapr-demo -p 8081` | http://localhost:8081 |
| Minikube | `minikube dashboard` | Opens automatically |

## Project Structure

```
deployments/kubernetes-phase7-ai/
├── config/
│   └── ingress-values.yaml
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-redis.yaml
│   ├── 02-rabbitmq.yaml
│   ├── 02-mongodb.yaml
│   ├── 03-components/
│   │   ├── statestore.yaml
│   │   ├── pubsub.yaml
│   │   ├── tracing.yaml
│   │   ├── conversation.yaml        # Anthropic LLM via Dapr Conversation API
│   │   └── templates/
│   ├── 04-catalog-service.yaml
│   ├── 05-order-service.yaml         # Updated: GET /orders endpoint
│   ├── 06-notification-service.yaml
│   ├── 07-workflow-service.yaml      # Updated: CheckFraudActivity (calls Conversation API)
│   ├── 08-web-app.yaml               # Updated: "Copy for AI" + 5-step saga display
│   ├── 09-ingress.yaml
│   └── 10-zipkin.yaml
├── scripts/
│   ├── setup-cluster.sh
│   ├── build-images.sh
│   ├── deploy-all.sh
│   ├── cleanup.sh
│   ├── test-services.sh
│   └── test-workflow.sh
├── README.md
└── ARCHITECTURE.md
```

## Useful Commands

```bash
# View all pods
kubectl get pods -n dapr-demo

# View workflow-service logs (see fraud check reasoning from Claude)
kubectl logs -f deployment/workflow-service -c workflow-service -n dapr-demo

# View order-service logs
kubectl logs -f deployment/order-service -c order-service -n dapr-demo
```

## Cleanup

```bash
./scripts/cleanup.sh
minikube stop
minikube delete
```
