import React, { useState, useEffect } from 'react';
import { getProducts, getOrders, getWorkflowInfo } from '../services/api';
import OrderForm from './OrderForm';
import ProductForm from './ProductForm';
import WorkflowOrderForm from './WorkflowOrderForm';
import OrdersPanel from './OrdersPanel';

function ProductList() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [showProductForm, setShowProductForm] = useState(false);
  const [useWorkflow, setUseWorkflow] = useState(false);
  const [skipFraudCheck, setSkipFraudCheck] = useState(false);
  const [workflowAvailable, setWorkflowAvailable] = useState(false);
  const [copyStatus, setCopyStatus] = useState(null);

  useEffect(() => {
    fetchProducts();
    checkWorkflowAvailable();
  }, []);

  const checkWorkflowAvailable = async () => {
    try {
      await getWorkflowInfo();
      setWorkflowAvailable(true);
      console.log('Workflow service available');
    } catch (err) {
      setWorkflowAvailable(false);
      console.log('Workflow service not available (Phase 5+ required)');
    }
  };

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const data = await getProducts();
      setProducts(data || []);
      setError(null);
    } catch (err) {
      setError(err.message || 'Failed to fetch products');
      console.error('Error fetching products:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleOrderClick = (product, workflow = false, noFraud = false) => {
    setSelectedProduct(product);
    setUseWorkflow(workflow);
    setSkipFraudCheck(noFraud);
  };

  const handleOrderComplete = () => {
    setSelectedProduct(null);
    setUseWorkflow(false);
    setSkipFraudCheck(false);
    // Refresh products to update stock
    fetchProducts();
  };

  const handleOrderCancel = () => {
    setSelectedProduct(null);
    setUseWorkflow(false);
    setSkipFraudCheck(false);
  };

  const handleCopyForAI = async () => {
    try {
      setCopyStatus('loading');

      let orders = [];
      try {
        orders = await getOrders() || [];
      } catch (err) {
        // Orders endpoint may not exist in older phases
      }

      const pendingOrders = orders.filter(o => o.status === 'pending_shipment');

      if (pendingOrders.length === 0) {
        await navigator.clipboard.writeText('No pending orders to review.');
        setCopyStatus('copied');
        setTimeout(() => setCopyStatus(null), 2000);
        return;
      }

      let text = 'You are reviewing e-commerce orders before shipment. For each order below,\n';
      text += 'assess the fraud risk and return a score from 0 (no risk) to 100 (certain fraud)\n';
      text += 'with brief reasoning.\n\n';
      text += '## Pending Orders\n\n';

      pendingOrders.forEach((o, i) => {
        text += `### Order ${i + 1}: ${o.orderId}\n`;
        text += `- Customer: ${o.customerName || 'Unknown'}\n`;
        text += `- Email: ${o.customerEmail || 'Unknown'}\n`;
        text += `- Product: ${o.productName || o.productId}\n`;
        if (o.productCategory) text += `- Category: ${o.productCategory}\n`;
        text += `- Quantity: ${o.quantity}\n`;
        text += `- Total: $${(o.total || 0).toFixed(2)}\n`;
        if (o.shippingAddress) text += `- Shipping Address: ${o.shippingAddress}\n`;
        if (o.orderTimestamp) text += `- Order Time: ${o.orderTimestamp}\n`;
        if (o.paymentTransactionId) text += `- Transaction: ${o.paymentTransactionId}\n`;
        text += '\n';
      });

      // Include all orders as history context
      const allOtherOrders = orders.filter(o => o.status !== 'pending_shipment');
      if (allOtherOrders.length > 0) {
        text += '## Order History (for context)\n\n';
        allOtherOrders.forEach(o => {
          text += `- ${o.customerName || '?'} (${o.customerEmail || '?'}): ${o.productName || o.productId}`;
          if (o.productCategory) text += ` [${o.productCategory}]`;
          text += ` x${o.quantity}, $${(o.total || 0).toFixed(2)}, status=${o.status}`;
          if (o.orderTimestamp) text += `, time=${o.orderTimestamp}`;
          text += '\n';
        });
        text += '\n';
      }

      text += 'For each order, respond with:\n';
      text += '- **Score**: 0-100\n';
      text += '- **Risk Level**: low (0-39), medium (40-69), high (70-79), critical (80+)\n';
      text += '- **Reasoning**: Brief explanation of risk factors\n';
      text += '- **Recommendation**: Ship or Cancel\n';

      await navigator.clipboard.writeText(text);
      setCopyStatus('copied');
      setTimeout(() => setCopyStatus(null), 2000);
    } catch (err) {
      console.error('Error copying for AI:', err);
      setCopyStatus('error');
      setTimeout(() => setCopyStatus(null), 2000);
    }
  };

  const handleAddProduct = () => {
    setShowProductForm(true);
  };

  const handleProductFormComplete = () => {
    setShowProductForm(false);
    fetchProducts(); // Refresh product list
  };

  const handleProductFormCancel = () => {
    setShowProductForm(false);
  };

  if (loading) {
    return <div className="loading">Loading products...</div>;
  }

  if (error) {
    return (
      <div className="error">
        <h3>Error loading products</h3>
        <p>{error}</p>
        <button onClick={fetchProducts}>Retry</button>
      </div>
    );
  }

  return (
    <div className="product-list">
      <div className="catalog-header">
        <h2>Product Catalog</h2>
        <div className="catalog-actions">
          <button
            className="copy-ai-button"
            onClick={handleCopyForAI}
            disabled={copyStatus === 'loading'}
            title="Copy pending orders for fraud review in Claude Desktop"
          >
            {copyStatus === 'loading' ? 'Loading...' : copyStatus === 'copied' ? 'Copied!' : copyStatus === 'error' ? 'Failed' : 'Copy for AI'}
          </button>
          <button className="add-product-button" onClick={handleAddProduct}>
            + Add Product
          </button>
        </div>
      </div>

      {products.length === 0 ? (
        <div className="empty">
          <h3>No products available</h3>
          <p>The catalog is empty. Click the button above to add your first product!</p>
        </div>
      ) : (
        <div className="products-grid">
        {products.map((product) => (
          <div key={product.id} className="product-card">
            <h3>{product.name}</h3>
            <p className="description">{product.description}</p>
            <div className="product-info">
              <span className="price">${product.price.toFixed(2)}</span>
              <span className="stock">Stock: {product.stock}</span>
            </div>
            <div className="order-buttons">
              <button
                className="order-button"
                onClick={() => handleOrderClick(product, false)}
                disabled={product.stock === 0}
              >
                {product.stock > 0 ? (workflowAvailable ? 'Quick Order' : 'Order Now') : 'Out of Stock'}
              </button>
              {workflowAvailable && (
                <>
                  <button
                    className="order-button workflow-button"
                    onClick={() => handleOrderClick(product, true, true)}
                    disabled={product.stock === 0}
                    title="Order with Saga Pattern (no AI fraud check)"
                  >
                    {product.stock > 0 ? 'Workflow Order' : 'Out of Stock'}
                  </button>
                  <button
                    className="order-button workflow-ai-button"
                    onClick={() => handleOrderClick(product, true, false)}
                    disabled={product.stock === 0}
                    title="Order with Saga Pattern + AI Fraud Check"
                  >
                    {product.stock > 0 ? 'Workflow + AI' : 'Out of Stock'}
                  </button>
                </>
              )}
            </div>
          </div>
        ))}
        </div>
      )}

      {selectedProduct && !useWorkflow && (
        <OrderForm
          product={selectedProduct}
          onComplete={handleOrderComplete}
          onCancel={handleOrderCancel}
        />
      )}

      {selectedProduct && useWorkflow && (
        <WorkflowOrderForm
          product={selectedProduct}
          onComplete={handleOrderComplete}
          onCancel={handleOrderCancel}
          skipFraudCheck={skipFraudCheck}
        />
      )}

      {showProductForm && (
        <ProductForm
          onComplete={handleProductFormComplete}
          onCancel={handleProductFormCancel}
        />
      )}

      <OrdersPanel onRefreshProducts={fetchProducts} />
    </div>
  );
}

export default ProductList;
