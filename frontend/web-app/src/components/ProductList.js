import React, { useState, useEffect } from 'react';
import { getProducts, getOrders, getWorkflowInfo } from '../services/api';
import OrderForm from './OrderForm';
import ProductForm from './ProductForm';
import WorkflowOrderForm from './WorkflowOrderForm';

function ProductList() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [showProductForm, setShowProductForm] = useState(false);
  const [useWorkflow, setUseWorkflow] = useState(false);
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

  const handleOrderClick = (product, workflow = false) => {
    setSelectedProduct(product);
    setUseWorkflow(workflow);
  };

  const handleOrderComplete = () => {
    setSelectedProduct(null);
    setUseWorkflow(false);
    // Refresh products to update stock
    fetchProducts();
  };

  const handleOrderCancel = () => {
    setSelectedProduct(null);
    setUseWorkflow(false);
  };

  const handleCopyForAI = async () => {
    try {
      setCopyStatus('loading');
      const currentProducts = products.length > 0 ? products : await getProducts();

      let orders = [];
      try {
        orders = await getOrders() || [];
      } catch (err) {
        // Orders may be empty, that's fine
      }

      let text = 'Here is my current product catalog and recent orders. Based on this data,\n';
      text += 'what additional products should I consider stocking?\n\n';
      text += '## Current Products\n';
      if (currentProducts.length === 0) {
        text += '(No products in catalog yet)\n';
      } else {
        currentProducts.forEach(p => {
          const stockNote = p.stock === 0 ? ' - out of stock' : '';
          text += `- ${p.name} ($${p.price.toFixed(2)}, ${p.stock} in stock${stockNote})\n`;
        });
      }

      text += '\n## Recent Orders\n';
      if (orders.length === 0) {
        text += '(No orders yet)\n';
      } else {
        orders.forEach(o => {
          text += `- Order ${o.orderId}: ${o.productName || o.productId} x${o.quantity} ($${(o.total || 0).toFixed(2)})\n`;
        });
      }

      text += '\nPlease suggest 3-5 new products with name, description, suggested price,\n';
      text += 'and reasoning based on the patterns you see.\n';

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
            title="Copy catalog and order data to paste into Claude Desktop"
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
                <button
                  className="order-button workflow-button"
                  onClick={() => handleOrderClick(product, true)}
                  disabled={product.stock === 0}
                  title="Order with Saga Pattern"
                >
                  {product.stock > 0 ? 'Workflow Order' : 'Out of Stock'}
                </button>
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
        />
      )}

      {showProductForm && (
        <ProductForm
          onComplete={handleProductFormComplete}
          onCancel={handleProductFormCancel}
        />
      )}
    </div>
  );
}

export default ProductList;
