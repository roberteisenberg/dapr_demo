# Phase 11: Resilience

Production-harden the application with Dapr resiliency policies, pub/sub dead letter handling, and horizontal pod autoscaling under load. All visible through Phase 4's Zipkin tracing.

> **Note**: Phase 11 layers on top of the existing deployment. It does not duplicate manifests from earlier phases. Prerequisite: Phase 10 (which implies Phases 6-9 deployed on AKS).

**Teaching Points:**
- "One YAML file adds retries, timeouts, and circuit breakers to every service call — zero code changes."
- "Dead letter topics catch failed messages instead of losing them."
- "HPA scales pods based on CPU — Dapr distributes load across instances automatically."

## Prerequisites

- AKS cluster running with Phases 6-10 deployed
- `hey` for load testing: `go install github.com/rakyll/hey@latest` (or `brew install hey`)
- `jq` and `python3` for test scripts
- Metrics server running (AKS includes this by default)

### Docker Image Update

The notification-service was updated to add dead letter handling. Rebuild and push:

```bash
cd /path/to/dapr_demo
docker build -t <your-dockerhub>/dapr-notification-service:latest services/notification-service
docker push <your-dockerhub>/dapr-notification-service:latest
```

Or use the existing `build-and-push.sh` from Phase 8.

## Quick Start

```bash
cd deployments/kubernetes-phase11-resilience

# Deploy resilience features on top of existing cluster
./scripts/deploy-resilience.sh

# Verify
./scripts/test-resilience.sh
```

## What Phase 11 Adds

### 1. Dapr Resiliency Policy (`manifests/resiliency.yaml`)

A single Kubernetes resource that applies to all four backend services:

| Policy | Configuration | Effect |
|--------|--------------|--------|
| **Retries** | Exponential backoff: 1s→2s→4s→8s→10s, 5 max | Failed service calls retry automatically |
| **Timeouts** | 10s for service calls, 5s for state store | Calls don't hang indefinitely |
| **Circuit Breaker** | Trips after 3 consecutive failures, 30s cooldown | Prevents cascading failures |

```bash
kubectl get resiliency -n dapr-demo
kubectl describe resiliency default-resilience -n dapr-demo
```

### 2. Pub/Sub Dead Letter Topic

Messages that the notification-service cannot process are routed to a dead letter topic instead of being lost.

| Topic | Route | Behavior |
|-------|-------|----------|
| `orders` | `/orders` | Normal processing. Returns `DROP` for poison messages. |
| `orders-deadletter` | `/orders-deadletter` | Captures dropped messages for inspection. |

View dead letters:

```bash
curl $BASE_URL/v1.0/invoke/notification-service/method/dead-letters
```

### 3. Horizontal Pod Autoscaler (`manifests/hpa.yaml`)

| Service | Min Pods | Max Pods | Target CPU |
|---------|----------|----------|------------|
| catalog-service | 1 | 5 | 70% |
| order-service | 1 | 5 | 70% |

```bash
kubectl get hpa -n dapr-demo
watch kubectl get hpa,pods -n dapr-demo
```

## Demo Walkthrough

### Demo 1: Circuit Breaker + Recovery

```bash
./scripts/demo-circuit-breaker.sh
```

1. Kill catalog-service (scale to 0)
2. order-service tries to call catalog-service
3. Dapr retries with exponential backoff (1s, 2s, 4s, 8s, 10s)
4. After 3 failures → circuit breaker trips → immediate failures
5. Bring catalog-service back
6. After 30s cooldown → circuit half-opens → test succeeds → closes

### Demo 2: Dead Letter Topic

```bash
./scripts/demo-dead-letter.sh
```

1. Publish a normal message → processed successfully
2. Publish a poison message (with `"poison": true`)
3. notification-service returns `DROP`
4. Dapr routes the message to `orders-deadletter` topic
5. notification-service captures it → viewable at `/dead-letters`

### Demo 3: Auto-Scaling Under Load

```bash
./scripts/demo-hpa-load.sh
```

1. Baseline: 1 pod each for catalog and order service
2. `hey` sends ~200 req/s for 60 seconds
3. CPU exceeds 70% target → HPA adds pods
4. Load distributed across pods (visible in Zipkin traces)
5. After load stops → pods scale back down (~2 min stabilization)

## Files

| File | Purpose |
|------|---------|
| `manifests/resiliency.yaml` | Dapr Resiliency CRD: retries, timeouts, circuit breakers |
| `manifests/hpa.yaml` | HPAs for catalog-service and order-service |
| `manifests/tracing.yaml` | Updated access control (adds `/dead-letters`) |
| `scripts/deploy-resilience.sh` | Applies manifests on top of existing deployment |
| `scripts/test-resilience.sh` | Automated resilience verification |
| `scripts/demo-circuit-breaker.sh` | Interactive circuit breaker demo |
| `scripts/demo-dead-letter.sh` | Interactive dead letter topic demo |
| `scripts/demo-hpa-load.sh` | Load test with HPA scaling demo |

### Service Code Change

| File | Change |
|------|--------|
| `services/notification-service/index.js` | Dead letter topic subscription + handler + `/dead-letters` endpoint |

## Troubleshooting

### Circuit breaker not tripping

Check the resiliency resource is applied and scoped correctly:

```bash
kubectl describe resiliency default-resilience -n dapr-demo
kubectl logs deployment/order-service -c daprd -n dapr-demo | grep -i resilien
```

### Dead letters not appearing

Verify the notification-service subscription includes the dead letter topic:

```bash
kubectl exec deployment/notification-service -c daprd -n dapr-demo -- \
    wget -q -O- http://localhost:3500/v1.0/metadata | python3 -m json.tool
```

Make sure the notification-service image was rebuilt after the Phase 11 code change.

### HPA not scaling / shows \<unknown\>

Verify metrics-server is running and pods have CPU requests:

```bash
kubectl get pods -n kube-system | grep metrics-server
kubectl describe hpa catalog-service-hpa -n dapr-demo
```

Metrics-server may take 1-2 minutes to start collecting data after first deployment.

## What We're Not Doing

| Item | Why |
|------|-----|
| Custom metrics HPA | CPU-based is sufficient for the demo; custom metrics would require Prometheus + adapter |
| Pod Disruption Budgets | Good practice but adds complexity without a clear teaching payoff |
| Distributed rate limiting | Dapr has middleware for this but it's orthogonal to resilience |
| Retry budgets | Dapr doesn't have built-in retry budgets; circuit breakers serve a similar purpose |
