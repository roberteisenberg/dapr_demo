import axios from 'axios';

// API base URL - uses proxy in development, direct URL in production
const API_BASE_URL = process.env.REACT_APP_API_URL || '';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Dapr service invocation helper
const daprInvoke = (serviceId, method, data = null, httpMethod = 'GET') => {
  const url = `/v1.0/invoke/${serviceId}/method${method}`;

  if (httpMethod === 'POST') {
    return api.post(url, data);
  } else if (httpMethod === 'GET') {
    return api.get(url);
  }

  throw new Error(`Unsupported HTTP method: ${httpMethod}`);
};

// Product API - calls catalog-service via Dapr
export const getProducts = async () => {
  const response = await daprInvoke('catalog-service', '/products', null, 'GET');
  return response.data;
};

export const getProduct = async (id) => {
  const response = await daprInvoke('catalog-service', `/products/${id}`, null, 'GET');
  return response.data;
};

export const createProduct = async (productData) => {
  const response = await daprInvoke('catalog-service', '/products', productData, 'POST');
  return response.data;
};

// Order API - calls order-service via Dapr
// Note: In Phase 5, this will switch to workflow-service for saga orchestration
export const createOrder = async (orderData) => {
  const response = await daprInvoke('order-service', '/orders', orderData, 'POST');
  return response.data;
};

export const getOrder = async (orderId) => {
  const response = await daprInvoke('order-service', `/orders/${orderId}`, null, 'GET');
  return response.data;
};

export default api;
