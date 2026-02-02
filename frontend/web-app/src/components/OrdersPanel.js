import React, { useState, useEffect, useCallback } from 'react';
import { getOrders, shipOrder, cancelOrder } from '../services/api';

function OrdersPanel({ onRefreshProducts }) {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(null);
  const [error, setError] = useState(null);

  const fetchOrders = useCallback(async () => {
    try {
      setLoading(true);
      const data = await getOrders() || [];
      // Show newest first
      setOrders(data.reverse());
      setError(null);
    } catch (err) {
      // Orders endpoint may not exist in older phases — that's fine
      setOrders([]);
      setError(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchOrders();
  }, [fetchOrders]);

  const handleShip = async (orderId) => {
    try {
      setActionLoading(orderId);
      await shipOrder(orderId);
      await fetchOrders();
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to ship order');
      setTimeout(() => setError(null), 3000);
    } finally {
      setActionLoading(null);
    }
  };

  const handleCancel = async (orderId) => {
    try {
      setActionLoading(orderId);
      await cancelOrder(orderId);
      await fetchOrders();
      if (onRefreshProducts) onRefreshProducts();
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to cancel order');
      setTimeout(() => setError(null), 3000);
    } finally {
      setActionLoading(null);
    }
  };

  const getStatusBadgeClass = (status) => {
    switch (status) {
      case 'pending_shipment': return 'badge-pending';
      case 'shipped': return 'badge-shipped';
      case 'cancelled': return 'badge-cancelled';
      default: return 'badge-default';
    }
  };

  const getStatusLabel = (status) => {
    switch (status) {
      case 'pending_shipment': return 'Pending Shipment';
      case 'shipped': return 'Shipped';
      case 'cancelled': return 'Cancelled';
      case 'created': return 'Created';
      default: return status || 'Unknown';
    }
  };

  const getFraudScoreClass = (score) => {
    if (score == null) return '';
    if (score < 40) return 'fraud-low';
    if (score < 70) return 'fraud-medium';
    if (score < 80) return 'fraud-high';
    return 'fraud-critical';
  };

  // Don't render if no orders exist (backward compat for phases without orders)
  if (!loading && orders.length === 0) {
    return null;
  }

  return (
    <div className="orders-panel">
      <div className="orders-header">
        <h2>Orders</h2>
        <button className="orders-refresh-btn" onClick={fetchOrders} disabled={loading}>
          {loading ? 'Loading...' : 'Refresh'}
        </button>
      </div>

      {error && <div className="orders-error">{error}</div>}

      {loading ? (
        <div className="orders-loading">Loading orders...</div>
      ) : (
        <div className="orders-table-wrap">
          <table className="orders-table">
            <thead>
              <tr>
                <th>Order</th>
                <th>Product</th>
                <th>Qty</th>
                <th>Total</th>
                <th>Customer</th>
                <th>Status</th>
                <th>Fraud</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr key={order.orderId} className="order-row">
                  <td className="order-id" title={order.orderId}>
                    {order.orderId.length > 16
                      ? '...' + order.orderId.slice(-12)
                      : order.orderId}
                  </td>
                  <td>
                    {order.productName || order.productId}
                    {order.productCategory && (
                      <span className="order-category"> [{order.productCategory}]</span>
                    )}
                  </td>
                  <td>{order.quantity}</td>
                  <td>${(order.total || 0).toFixed(2)}</td>
                  <td title={order.shippingAddress || ''}>
                    {order.customerName || '-'}
                    {order.shippingAddress && <span className="order-address-hint"> *</span>}
                  </td>
                  <td>
                    <span className={`status-badge ${getStatusBadgeClass(order.status)}`}>
                      {getStatusLabel(order.status)}
                    </span>
                  </td>
                  <td>
                    {order.fraudScore != null ? (
                      <span
                        className={`fraud-score ${getFraudScoreClass(order.fraudScore)}`}
                        title={order.fraudReasoning || 'No reasoning available'}
                      >
                        {order.fraudScore}
                      </span>
                    ) : (
                      <span className="fraud-score fraud-na">-</span>
                    )}
                  </td>
                  <td className="order-actions">
                    {order.status === 'pending_shipment' && (
                      <>
                        <button
                          className="btn-ship"
                          onClick={() => handleShip(order.orderId)}
                          disabled={actionLoading === order.orderId}
                        >
                          Ship
                        </button>
                        <button
                          className="btn-cancel-order"
                          onClick={() => handleCancel(order.orderId)}
                          disabled={actionLoading === order.orderId}
                        >
                          Cancel
                        </button>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export default OrdersPanel;
