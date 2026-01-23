# Dapr Components - Swappable Pub/Sub

This directory demonstrates **Dapr's component portability** - swap infrastructure without changing application code!

## Available Pub/Sub Components

- **`pubsub-redis.yaml`** - Redis pub/sub (uses dapr_redis from `dapr init`)
- **`pubsub-rabbitmq.yaml`** - RabbitMQ pub/sub

## How to Switch Between Them

Templates are stored in `components/templates/` to avoid Dapr loading conflicts.

Copy the template you want to use:

```bash
# Use Redis
cp components/templates/pubsub-redis.yaml components/pubsub.yaml

# Use RabbitMQ
cp components/templates/pubsub-rabbitmq.yaml components/pubsub.yaml
```

## Prerequisites

### For Redis (Default)
Already running from `dapr init`:
```bash
docker ps | grep dapr_redis
```

### For RabbitMQ
Start RabbitMQ container:
```bash
./scripts/start-rabbitmq.sh

# Wait ~10 seconds for startup
```

## Test Both

```bash
# 1. Stop services if running (Ctrl+C)

# 2. Switch component (copy pubsub-redis.yaml or pubsub-rabbitmq.yaml to pubsub.yaml)

# 3. Start services
dapr run -f .

# 4. Test (same test script works with both!)
./scripts/test-local.sh
```

## The Magic: ZERO Code Changes!

**Order Service (app.py)** - Same code for both:
```python
d.publish_event(
    pubsub_name='pubsub',  # ← Just references the component name
    topic_name='orders',
    data=json.dumps(order)
)
```

**Notification Service (index.js)** - Same code for both:
```javascript
{
    pubsubname: 'pubsub',  // ← Just references the component name
    topic: 'orders',
    route: '/orders'
}
```

**Only the YAML changes!** That's Dapr's component abstraction. 🎯

## Comparison

| Feature | Redis | RabbitMQ |
|---------|-------|----------|
| **Setup** | Included with Dapr | Requires container |
| **Management UI** | ❌ No | ✅ Yes (http://localhost:15672) |
| **Persistence** | Optional | Optional |
| **Production Use** | ✅ Common | ✅ Common |
| **Message Routing** | Simple | Advanced |

## View Messages

### Redis
```bash
docker exec -it dapr_redis redis-cli
PSUBSCRIBE *
```

### RabbitMQ
Open http://localhost:15672 (guest/guest)
→ Queues tab → See `orders` queue
