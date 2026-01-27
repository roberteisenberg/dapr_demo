import React, { useState, useEffect } from 'react';
import { getProducts, getWorkflowInfo } from '../services/api';
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
        <button className="add-product-button" onClick={handleAddProduct}>
          + Add Product
        </button>
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
