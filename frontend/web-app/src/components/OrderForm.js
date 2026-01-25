import React, { useState } from 'react';
import { createOrder } from '../services/api';

function OrderForm({ product, onComplete, onCancel }) {
  const [quantity, setQuantity] = useState(1);
  const [orderId, setOrderId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!orderId.trim()) {
      setError('Order ID is required');
      return;
    }

    if (quantity < 1 || quantity > product.stock) {
      setError(`Quantity must be between 1 and ${product.stock}`);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const orderData = {
        orderId: orderId.trim(),
        productId: product.id,
        quantity: parseInt(quantity, 10),
      };

      const result = await createOrder(orderData);
      console.log('Order created:', result);

      setSuccess(true);
      setTimeout(() => {
        onComplete();
      }, 2000);
    } catch (err) {
      const errorMessage = err.response?.data?.error || err.message || 'Failed to create order';
      setError(errorMessage);
      console.error('Error creating order:', err);
    } finally {
      setLoading(false);
    }
  };

  const total = (product.price * quantity).toFixed(2);

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onCancel()}>
      <div className="modal">
        <h2>Create Order</h2>

        {success ? (
          <div className="success-message">
            <h3>Order Created!</h3>
            <p>Your order has been placed and notification sent.</p>
          </div>
        ) : (
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label>Product:</label>
              <p className="product-name">{product.name}</p>
            </div>

            <div className="form-group">
              <label htmlFor="orderId">Order ID:</label>
              <input
                type="text"
                id="orderId"
                value={orderId}
                onChange={(e) => setOrderId(e.target.value)}
                placeholder="e.g., order-12345"
                required
                disabled={loading}
              />
            </div>

            <div className="form-group">
              <label htmlFor="quantity">Quantity:</label>
              <input
                type="number"
                id="quantity"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                min="1"
                max={product.stock}
                required
                disabled={loading}
              />
              <span className="hint">Available: {product.stock}</span>
            </div>

            <div className="form-group">
              <label>Total:</label>
              <p className="total">${total}</p>
            </div>

            {error && (
              <div className="error-message">
                {error}
              </div>
            )}

            <div className="form-actions">
              <button
                type="button"
                onClick={onCancel}
                className="cancel-button"
                disabled={loading}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="submit-button"
                disabled={loading}
              >
                {loading ? 'Creating Order...' : 'Create Order'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

export default OrderForm;
