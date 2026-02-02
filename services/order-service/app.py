import json
import logging
from flask import Flask, request, jsonify
from dapr.clients import DaprClient
from dapr.ext.grpc import App

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
dapr_app = App()

DAPR_STORE_NAME = "statestore"
PUBSUB_NAME = "pubsub"
TOPIC_NAME = "orders"
ORDER_INDEX_KEY = "order-index"

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200

@app.route('/orders', methods=['POST'])
def create_order():
    """Create a new order"""
    try:
        order_data = request.json
        order_id = order_data.get('orderId')
        product_id = order_data.get('productId')
        quantity = order_data.get('quantity', 1)

        if not order_id or not product_id:
            return jsonify({"error": "orderId and productId are required"}), 400

        logger.info(f"Creating order: {order_id} for product: {product_id}")

        # Call Catalog Service via Dapr service invocation to check inventory
        with DaprClient() as d:
            # Invoke catalog service
            try:
                result = d.invoke_method(
                    app_id='catalog-service',
                    method_name=f'products/{product_id}',
                    http_verb='GET'
                )
                product = json.loads(result.data)
                logger.info(f"Product found: {product.get('name')} - Stock: {product.get('stock')}")

                # Check if enough stock
                if product.get('stock', 0) < quantity:
                    return jsonify({
                        "error": "Insufficient stock",
                        "available": product.get('stock', 0),
                        "requested": quantity
                    }), 400

            except Exception as e:
                logger.error(f"Error calling catalog service: {e}")
                return jsonify({"error": f"Product not found: {product_id}"}), 404

            # Save order to state store
            order = {
                "orderId": order_id,
                "productId": product_id,
                "productName": product.get('name'),
                "quantity": quantity,
                "price": product.get('price'),
                "total": product.get('price', 0) * quantity,
                "status": "created"
            }

            d.save_state(
                store_name=DAPR_STORE_NAME,
                key=order_id,
                value=json.dumps(order)
            )
            logger.info(f"Order saved to state store: {order_id}")

            # Update order index
            try:
                index_result = d.get_state(store_name=DAPR_STORE_NAME, key=ORDER_INDEX_KEY)
                order_ids = json.loads(index_result.data) if index_result.data else []
            except Exception:
                order_ids = []
            if order_id not in order_ids:
                order_ids.append(order_id)
                d.save_state(store_name=DAPR_STORE_NAME, key=ORDER_INDEX_KEY, value=json.dumps(order_ids))

            # Publish OrderCreated event
            d.publish_event(
                pubsub_name=PUBSUB_NAME,
                topic_name=TOPIC_NAME,
                data=json.dumps(order),
                data_content_type='application/json'
            )
            logger.info(f"OrderCreated event published for: {order_id}")

            return jsonify(order), 201

    except Exception as e:
        logger.error(f"Error creating order: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/orders', methods=['GET'])
def list_orders():
    """List all orders"""
    try:
        with DaprClient() as d:
            index_result = d.get_state(store_name=DAPR_STORE_NAME, key=ORDER_INDEX_KEY)
            order_ids = json.loads(index_result.data) if index_result.data else []

            orders = []
            for oid in order_ids:
                result = d.get_state(store_name=DAPR_STORE_NAME, key=oid)
                if result.data:
                    orders.append(json.loads(result.data))

            return jsonify(orders), 200

    except Exception as e:
        logger.error(f"Error listing orders: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/orders/record', methods=['POST'])
def record_order():
    """Record a workflow order into the state store (called by RecordOrderActivity)"""
    try:
        order_data = request.json
        order_id = order_data.get('orderId')

        if not order_id:
            return jsonify({"error": "orderId is required"}), 400

        logger.info(f"Recording workflow order: {order_id}")

        with DaprClient() as d:
            order = {
                "orderId": order_id,
                "productId": order_data.get('productId'),
                "productName": order_data.get('productName'),
                "productCategory": order_data.get('productCategory'),
                "quantity": order_data.get('quantity'),
                "price": order_data.get('price'),
                "total": order_data.get('total'),
                "status": order_data.get('status', 'pending_shipment'),
                "customerName": order_data.get('customerName'),
                "customerEmail": order_data.get('customerEmail'),
                "shippingAddress": order_data.get('shippingAddress'),
                "orderTimestamp": order_data.get('orderTimestamp'),
                "paymentTransactionId": order_data.get('paymentTransactionId'),
                "fraudScore": order_data.get('fraudScore'),
                "fraudReasoning": order_data.get('fraudReasoning'),
            }

            d.save_state(
                store_name=DAPR_STORE_NAME,
                key=order_id,
                value=json.dumps(order)
            )

            # Update order index
            try:
                index_result = d.get_state(store_name=DAPR_STORE_NAME, key=ORDER_INDEX_KEY)
                order_ids = json.loads(index_result.data) if index_result.data else []
            except Exception:
                order_ids = []
            if order_id not in order_ids:
                order_ids.append(order_id)
                d.save_state(store_name=DAPR_STORE_NAME, key=ORDER_INDEX_KEY, value=json.dumps(order_ids))

            logger.info(f"Workflow order recorded: {order_id}")
            return jsonify(order), 201

    except Exception as e:
        logger.error(f"Error recording order: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/orders/<order_id>/ship', methods=['POST'])
def ship_order(order_id):
    """Ship a pending order"""
    try:
        with DaprClient() as d:
            result = d.get_state(store_name=DAPR_STORE_NAME, key=order_id)
            if not result.data:
                return jsonify({"error": "Order not found"}), 404

            order = json.loads(result.data)
            if order.get('status') != 'pending_shipment':
                return jsonify({"error": f"Cannot ship order with status '{order.get('status')}'. Must be 'pending_shipment'."}), 400

            order['status'] = 'shipped'
            from datetime import datetime, timezone
            order['shippedAt'] = datetime.now(timezone.utc).isoformat()

            d.save_state(store_name=DAPR_STORE_NAME, key=order_id, value=json.dumps(order))
            logger.info(f"Order shipped: {order_id}")
            return jsonify(order), 200

    except Exception as e:
        logger.error(f"Error shipping order: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/orders/<order_id>/cancel', methods=['POST'])
def cancel_order(order_id):
    """Cancel a pending order and restore inventory"""
    try:
        with DaprClient() as d:
            result = d.get_state(store_name=DAPR_STORE_NAME, key=order_id)
            if not result.data:
                return jsonify({"error": "Order not found"}), 404

            order = json.loads(result.data)
            if order.get('status') != 'pending_shipment':
                return jsonify({"error": f"Cannot cancel order with status '{order.get('status')}'. Must be 'pending_shipment'."}), 400

            # Restore inventory
            product_id = order.get('productId')
            quantity = order.get('quantity', 0)
            if product_id and quantity > 0:
                try:
                    product_result = d.invoke_method(
                        app_id='catalog-service',
                        method_name=f'products/{product_id}',
                        http_verb='GET'
                    )
                    product = json.loads(product_result.data)
                    product['stock'] = product.get('stock', 0) + quantity

                    d.invoke_method(
                        app_id='catalog-service',
                        method_name=f'products/{product_id}',
                        data=json.dumps(product),
                        http_verb='PUT'
                    )
                    logger.info(f"Restored {quantity} units of {product_id}")
                except Exception as e:
                    logger.error(f"Failed to restore inventory for {product_id}: {e}")

            order['status'] = 'cancelled'
            from datetime import datetime, timezone
            order['cancelledAt'] = datetime.now(timezone.utc).isoformat()

            d.save_state(store_name=DAPR_STORE_NAME, key=order_id, value=json.dumps(order))
            logger.info(f"Order cancelled: {order_id}")
            return jsonify(order), 200

    except Exception as e:
        logger.error(f"Error cancelling order: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    """Get an order by ID"""
    try:
        with DaprClient() as d:
            result = d.get_state(
                store_name=DAPR_STORE_NAME,
                key=order_id
            )

            if not result.data:
                return jsonify({"error": "Order not found"}), 404

            order = json.loads(result.data)
            return jsonify(order), 200

    except Exception as e:
        logger.error(f"Error getting order: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    logger.info("Order Service starting on port 8081")
    app.run(host='0.0.0.0', port=8081)
