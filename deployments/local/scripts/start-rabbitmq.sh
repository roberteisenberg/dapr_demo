#!/bin/bash

echo "Starting RabbitMQ container..."
echo ""

# Check if RabbitMQ container already exists
if docker ps -a --format '{{.Names}}' | grep -q '^rabbitmq$'; then
    echo "RabbitMQ container exists, starting it..."
    docker start rabbitmq
else
    echo "Creating new RabbitMQ container..."
    docker run -d \
      --name rabbitmq \
      -p 5672:5672 \
      -p 15672:15672 \
      rabbitmq:3-management
fi

echo ""
echo "✅ RabbitMQ started!"
echo ""
echo "Ports:"
echo "  - AMQP:       localhost:5672"
echo "  - Management: http://localhost:15672"
echo "  - Credentials: guest / guest"
echo ""
echo "Wait ~10 seconds for RabbitMQ to fully start..."
