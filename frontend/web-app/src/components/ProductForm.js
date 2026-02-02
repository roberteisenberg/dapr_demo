import React, { useState } from 'react';
import { createProduct } from '../services/api';

function ProductForm({ onComplete, onCancel }) {
  const [formData, setFormData] = useState({
    id: '',
    name: '',
    description: '',
    price: '',
    stock: '',
    category: '',
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(false);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    // Validation
    if (!formData.id.trim() || !formData.name.trim()) {
      setError('Product ID and Name are required');
      return;
    }

    if (parseFloat(formData.price) <= 0) {
      setError('Price must be greater than 0');
      return;
    }

    if (parseInt(formData.stock) < 0) {
      setError('Stock cannot be negative');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const productData = {
        id: formData.id.trim(),
        name: formData.name.trim(),
        description: formData.description.trim(),
        price: parseFloat(formData.price),
        stock: parseInt(formData.stock, 10),
        category: formData.category || undefined,
      };

      const result = await createProduct(productData);
      console.log('Product created:', result);

      setSuccess(true);
      setTimeout(() => {
        onComplete();
      }, 2000);
    } catch (err) {
      const errorMessage = err.response?.data?.error || err.message || 'Failed to create product';
      setError(errorMessage);
      console.error('Error creating product:', err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onCancel()}>
      <div className="modal">
        <h2>Add New Product</h2>

        {success ? (
          <div className="success-message">
            <h3>Product Created Successfully!</h3>
            <p>The product has been added to the catalog.</p>
          </div>
        ) : (
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label htmlFor="id">Product ID:</label>
              <input
                type="text"
                id="id"
                name="id"
                value={formData.id}
                onChange={handleChange}
                placeholder="e.g., laptop-001"
                required
                disabled={loading}
              />
              <span className="hint">Unique identifier for the product</span>
            </div>

            <div className="form-group">
              <label htmlFor="name">Product Name:</label>
              <input
                type="text"
                id="name"
                name="name"
                value={formData.name}
                onChange={handleChange}
                placeholder="e.g., Gaming Laptop"
                required
                disabled={loading}
              />
            </div>

            <div className="form-group">
              <label htmlFor="description">Description:</label>
              <textarea
                id="description"
                name="description"
                value={formData.description}
                onChange={handleChange}
                placeholder="Product description..."
                rows="3"
                disabled={loading}
              />
            </div>

            <div className="form-group">
              <label htmlFor="category">Category:</label>
              <select
                id="category"
                name="category"
                value={formData.category}
                onChange={handleChange}
                disabled={loading}
              >
                <option value="">-- Select category --</option>
                <option value="electronics">Electronics</option>
                <option value="gift-cards">Gift Cards</option>
                <option value="clothing">Clothing</option>
                <option value="office-supplies">Office Supplies</option>
                <option value="home-garden">Home & Garden</option>
                <option value="sports">Sports & Outdoors</option>
                <option value="other">Other</option>
              </select>
            </div>

            <div className="form-group">
              <label htmlFor="price">Price ($):</label>
              <input
                type="number"
                id="price"
                name="price"
                value={formData.price}
                onChange={handleChange}
                placeholder="99.99"
                step="0.01"
                min="0.01"
                required
                disabled={loading}
              />
            </div>

            <div className="form-group">
              <label htmlFor="stock">Stock Quantity:</label>
              <input
                type="number"
                id="stock"
                name="stock"
                value={formData.stock}
                onChange={handleChange}
                placeholder="10"
                min="0"
                required
                disabled={loading}
              />
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
                {loading ? 'Creating Product...' : 'Create Product'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

export default ProductForm;
