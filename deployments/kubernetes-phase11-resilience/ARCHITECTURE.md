# Phase 11: Resilience Architecture

## Overview

Phase 11 adds three resilience layers on top of the AKS deployment from Phases 6-10. Each addresses a different failure mode:

```
┌─────────────────────────────────────────────────────────────────┐
│                   Request Flow with Resilience                   │
│                                                                  │
│  Client → Ingress → Dapr Sidecar                                │
│                         │                                        │
│             ┌───────────▼───────────────┐                       │
│             │  Resiliency Policy        │                       │
│             │  ┌─────────────────────┐  │                       │
│             │  │ 1. Timeout (10s)    │  │                       │
│             │  │ 2. Retry (exp. bo)  │  │                       │
│             │  │ 3. Circuit Breaker  │  │                       │
│             │  └─────────────────────┘  │                       │
│             └───────────┬───────────────┘                       │
│                         ▼                                        │
│             Target Service (auto-scaled by HPA)                  │
│                                                                  │
│  Pub/Sub Flow:                                                   │
│  Publisher → Dapr → Redis → Dapr → Subscriber                   │
│                                      │                           │
│                               ┌──────▼──────┐                   │
│                               │ DROP status? │                   │
│                               └──┬───────┬──┘                   │
│                              yes │       │ no                    │
│                      ┌───────────▼┐   ┌──▼──────────┐           │
│                      │ Dead Letter │   │ Success     │           │
│                      │ Topic       │   │ (ACK)       │           │
│                      └────────────┘   └─────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## 1. Dapr Resiliency Policy

### How It Works

The Dapr Resiliency CRD is a Kubernetes resource that the Dapr sidecar reads at startup. It defines named policies (retries, timeouts, circuit breakers) and targets (which apps and components to apply them to). The application code is completely unaware — the sidecar handles everything.

### Retry: Exponential Backoff

```
Attempt 1: immediate
Attempt 2: wait 1s
Attempt 3: wait 2s
Attempt 4: wait 4s
Attempt 5: wait 8s
Attempt 6: wait 10s (capped at maxInterval)
→ give up after 5 retries
```

The multiplier is 2x by default. `duration` sets the initial interval (1s), `maxInterval` caps the backoff (10s).

### Circuit Breaker: Three States

```
CLOSED ──(3 consecutive failures)──→ OPEN
                                       │
                                  (wait 30s)
                                       │
                                       ▼
                                   HALF-OPEN
                                       │
                                 (allow 1 request)
                                    ╱       ╲
                                success    failure
                                  │           │
                                  ▼           ▼
                               CLOSED       OPEN
```

- `maxRequests: 1` — only 1 request allowed in half-open state
- `timeout: 30s` — time in open state before transitioning to half-open
- `trip: consecutiveFailures >= 3` — condition to trip from closed to open

**Why these values?** 3 failures is aggressive enough for a demo (you'll see the circuit trip quickly) but not so aggressive that transient errors trip it. 30s cooldown is long enough to see "open" state but short enough that recovery is visible in under a minute. Production systems typically use 5-10 failures and 60-120s cooldown.

### Target Mapping

| Target | Type | Policies Applied |
|--------|------|------------------|
| catalog-service | app (service invocation) | serviceTimeout, serviceRetry, serviceCB |
| order-service | app (service invocation) | serviceTimeout, serviceRetry, serviceCB |
| statestore | component (outbound) | stateTimeout, stateRetry |
| pubsub | component (outbound) | pubsubTimeout, pubsubRetry |

### Zero Code Changes

This is the key teaching point: `resiliency.yaml` is applied as a Kubernetes resource. The Dapr sidecar reads it on startup. No service code references retry counts, timeout durations, or circuit breaker thresholds. To change the policy, edit the YAML and restart the pods.

## 2. Dead Letter Topics

### How It Works

Dapr's dead letter mechanism is configured on the **subscription**, not the pub/sub component. When a subscriber returns `{"status": "DROP"}` for a message, Dapr checks if that subscription has a `deadLetterTopic` configured. If so, the message is re-published to the dead letter topic. If not, the message is discarded with a warning log.

### Message Flow

```
order-service publishes to "orders" topic
                │
                ▼
Redis Streams (pubsub component)
                │
                ▼
Dapr delivers to notification-service POST /orders
                │
          ┌─────┴─────┐
          │ poison?    │
          │            │
     no   ▼       yes  ▼
  {"status":    {"status":
   "SUCCESS"}    "DROP"}
          │            │
          ▼            ▼
       (done)    Dapr re-publishes to "orders-deadletter"
                       │
                       ▼
                notification-service POST /orders-deadletter
                       │
                       ▼
                Stored in memory → GET /dead-letters
```

### Subscriber Response Status Values

| Status | Meaning | Dead Letter? |
|--------|---------|-------------|
| `SUCCESS` | Message processed | No |
| `RETRY` | Redeliver the message | No (retried) |
| `DROP` | Discard the message | Yes (if deadLetterTopic configured) |

### Code Change Summary

The notification-service (`services/notification-service/index.js`) is the only service code modified in Phase 11:

1. Add `deadLetterTopic: 'orders-deadletter'` to the programmatic subscription
2. Add a second subscription for the dead letter topic itself
3. Add poison detection (check for `poison: true`) in the `/orders` handler
4. Add `POST /orders-deadletter` handler (stores in memory array)
5. Add `GET /dead-letters` endpoint (returns the in-memory store)

## 3. Horizontal Pod Autoscaler

### How It Works

HPA monitors CPU metrics (from metrics-server) and adjusts replica count to keep utilization near the target (70%):

```
desiredReplicas = ceil(currentReplicas * (currentCPU / targetCPU))

Example: 1 pod at 140% CPU, target 70%
→ ceil(1 * (140 / 70)) = ceil(2.0) = 2 pods
```

### Scaling Behavior

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Target CPU | 70% of request (50m = 35m threshold) | Leaves headroom for spikes |
| Scale-up window | 30s | Aggressive for demo visibility |
| Scale-up rate | 2 pods per 30s | Fast scaling for demo |
| Scale-down window | 120s | Prevents flapping |
| Scale-down rate | 1 pod per 60s | Gradual reduction |
| Min replicas | 1 | Cost-efficient baseline |
| Max replicas | 5 | Sufficient for demo |

### Why Only Catalog and Order Services?

| Service | Direct HTTP Load | HPA Benefit |
|---------|-----------------|-------------|
| catalog-service | Yes (GET/POST /products) | High — scales with traffic |
| order-service | Yes (POST/GET /orders) | High — scales with traffic |
| notification-service | No (pub/sub consumer) | Low — scaling doesn't help throughput |
| workflow-service | Moderate (POST /workflows) | Low — long-running, CPU isn't the bottleneck |

### Interaction with Dapr

When HPA scales a deployment from 1 to 3 pods, each new pod gets its own Dapr sidecar (via sidecar injection). Dapr's service invocation automatically discovers and load-balances across all instances. No configuration change needed — the resiliency policy, tracing, and access control apply to all pods identically.

In Zipkin, you'll see traces distributed across different pod instances.

## Design Decisions

### Single Resiliency Resource vs. Per-Service

A single `Resiliency` resource with `scopes` listing all services keeps the demo simple. In production, you might have per-service policies (different timeouts for slow services, different retry counts for idempotent vs. non-idempotent operations).

### In-Memory Dead Letter Store

Dead letters are stored in an in-memory array — they're lost when the pod restarts. For production, you'd persist to a state store or database. The in-memory approach keeps the code minimal and avoids adding a new Dapr component.

### `hey` vs. `k6` for Load Testing

`hey` is a single static binary with no dependencies. `k6` is more powerful (scripting, scenarios) but requires JavaScript test scripts. For generating sustained HTTP load to trigger HPA, `hey` is sufficient and easier to install.

### Layering on Phase 10 (No Copied Manifests)

Phase 11 follows the Phase 10 pattern — it layers new resources on top of the running cluster rather than copying all manifests from Phase 8. This keeps the phase focused on what's new (resiliency, HPA, dead letters) and avoids maintaining duplicate manifest files.
