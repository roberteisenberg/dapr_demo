const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json({ type: 'application/*+json' }));
app.use(bodyParser.json());

const PORT = process.env.PORT || 8082;
const PUBSUB_NAME = 'pubsub';
const TOPIC_NAME = 'orders';
const DEAD_LETTER_TOPIC = 'orders-deadletter';

// In-memory store for dead-lettered messages (demo purposes)
const deadLetters = [];

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

// Dapr subscription endpoint
app.get('/dapr/subscribe', (req, res) => {
    const subscriptions = [
        {
            pubsubname: PUBSUB_NAME,
            topic: TOPIC_NAME,
            route: '/orders',
            deadLetterTopic: DEAD_LETTER_TOPIC
        },
        {
            pubsubname: PUBSUB_NAME,
            topic: DEAD_LETTER_TOPIC,
            route: '/orders-deadletter'
        }
    ];
    console.log('Subscriptions configured:', JSON.stringify(subscriptions, null, 2));
    res.json(subscriptions);
});

// Handle OrderCreated events
app.post('/orders', (req, res) => {
    try {
        const order = req.body.data;

        // Poison message detection: reject messages with poison:true
        // Dapr routes dropped messages to the dead letter topic
        if (order && order.poison === true) {
            console.log('POISON MESSAGE DETECTED - rejecting');
            console.log(`Order ID: ${order.orderId}`);
            console.log('Returning DROP status to trigger dead letter routing');
            console.log('');
            return res.json({ status: 'DROP' });
        }

        console.log('ORDER NOTIFICATION RECEIVED');
        console.log('=====================================');
        console.log(`Order ID: ${order.orderId}`);
        console.log(`Product: ${order.productName}`);
        console.log(`Quantity: ${order.quantity}`);
        console.log(`Total: $${order.total}`);
        console.log(`Status: ${order.status}`);
        console.log('=====================================');
        console.log('Sending notification email...');
        console.log('Notification sent successfully');
        console.log('');

        res.json({ status: 'SUCCESS' });
    } catch (error) {
        console.error('Error processing order event:', error);
        res.json({ status: 'DROP' });
    }
});

// Handle dead-lettered messages
app.post('/orders-deadletter', (req, res) => {
    const message = req.body.data || req.body;
    const timestamp = new Date().toISOString();

    console.log('DEAD LETTER RECEIVED');
    console.log('=====================================');
    console.log(`Timestamp: ${timestamp}`);
    console.log(`Data: ${JSON.stringify(message, null, 2)}`);
    console.log('=====================================');
    console.log('');

    deadLetters.push({
        timestamp,
        data: message,
        topic: 'orders',
        reason: 'Message was dropped by subscriber'
    });

    res.json({ status: 'SUCCESS' });
});

// View dead-lettered messages
app.get('/dead-letters', (req, res) => {
    res.json({
        count: deadLetters.length,
        messages: deadLetters
    });
});

app.listen(PORT, () => {
    console.log(`Notification Service listening on port ${PORT}`);
    console.log(`Subscribed to topic '${TOPIC_NAME}' on pubsub '${PUBSUB_NAME}'`);
    console.log(`Dead letter topic: '${DEAD_LETTER_TOPIC}'`);
});
