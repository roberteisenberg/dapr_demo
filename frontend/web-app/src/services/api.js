import axios from 'axios';
import { addLog, parseDaprUrl, formatDescription, LogType } from './statusLog';

// API base URL - uses proxy in development, direct URL in production
const API_BASE_URL = process.env.REACT_APP_API_URL || '';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor - log outgoing Dapr calls
api.interceptors.request.use((config) => {
  config._startTime = Date.now();
  const daprInfo = parseDaprUrl(config.url);
  const httpMethod = (config.method || 'GET').toUpperCase();
  addLog({
    type: LogType.REQUEST,
    httpMethod,
    url: config.url,
    daprInfo,
    description: formatDescription(httpMethod, daprInfo),
  });
  return config;
});

// Response interceptor - log results with duration
api.interceptors.response.use(
  (response) => {
    const duration = response.config._startTime
      ? Date.now() - response.config._startTime
      : null;
    const daprInfo = parseDaprUrl(response.config.url);
    const httpMethod = (response.config.method || 'GET').toUpperCase();
    addLog({
      type: LogType.RESPONSE,
      httpMethod,
      url: response.config.url,
      status: response.status,
      daprInfo,
      description: formatDescription(httpMethod, daprInfo),
      duration,
    });
    return response;
  },
  (error) => {
    const config = error.config || {};
    const duration = config._startTime ? Date.now() - config._startTime : null;
    const daprInfo = parseDaprUrl(config.url);
    const httpMethod = (config.method || 'GET').toUpperCase();
    addLog({
      type: LogType.ERROR,
      httpMethod,
      url: config.url,
      status: error.response?.status,
      daprInfo,
      description: formatDescription(httpMethod, daprInfo),
      duration,
      error: error.message,
    });
    return Promise.reject(error);
  }
);

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
export const createOrder = async (orderData) => {
  const response = await daprInvoke('order-service', '/orders', orderData, 'POST');
  return response.data;
};

export const getOrder = async (orderId) => {
  const response = await daprInvoke('order-service', `/orders/${orderId}`, null, 'GET');
  return response.data;
};

export const getOrders = async () => {
  const response = await daprInvoke('order-service', '/orders', null, 'GET');
  return response.data;
};

// Workflow API - calls workflow-service via Dapr (Phase 5+)
// Uses saga pattern with automatic compensation on failure
export const startWorkflow = async (orderData) => {
  const response = await daprInvoke('workflow-service', '/workflows/order', orderData, 'POST');
  return response.data;
};

export const getWorkflowStatus = async (instanceId) => {
  const response = await daprInvoke('workflow-service', `/workflows/${instanceId}`, null, 'GET');
  return response.data;
};

export const getWorkflowInfo = async () => {
  const response = await daprInvoke('workflow-service', '/workflows', null, 'GET');
  return response.data;
};

export default api;
