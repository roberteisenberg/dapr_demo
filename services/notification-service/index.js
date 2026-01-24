const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json({ type: 'application/*+json' }));

const PORT = process.env.PORT || 8082;
const PUBSUB_NAME = 'pubsub';
const TOPIC_NAME = 'orders';

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
            route: '/orders'
        }
    ];
    console.log('Subscriptions configured:', JSON.stringify(subscriptions, null, 2));
    res.json(subscriptions);
});

// Handle OrderCreated events
app.post('/orders', (req, res) => {
    try {
        const order = req.body.data;
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

        res.status(200).send();
    } catch (error) {
        console.error('Error processing order event:', error);
        res.status(500).send();
    }
});

app.listen(PORT, () => {
    console.log(`Notification Service listening on port ${PORT}`);
    console.log(`Subscribed to topic '${TOPIC_NAME}' on pubsub '${PUBSUB_NAME}'`);
});
