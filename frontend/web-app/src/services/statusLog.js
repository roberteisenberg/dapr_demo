// Simple pub/sub log store for tracking Dapr operations
// No React dependency - pure JS module singleton

let logs = [];
let subscribers = [];
let idCounter = 0;

const MAX_LOGS = 200;

export const LogType = {
  REQUEST: 'request',
  RESPONSE: 'response',
  ERROR: 'error',
  INFO: 'info',
};

export function addLog(entry) {
  const log = {
    id: ++idCounter,
    timestamp: new Date(),
    ...entry,
  };
  logs = [log, ...logs].slice(0, MAX_LOGS);
  subscribers.forEach(fn => fn(logs));
  return log;
}

export function getLogs() {
  return logs;
}

export function clearLogs() {
  logs = [];
  idCounter = 0;
  subscribers.forEach(fn => fn(logs));
}

export function subscribe(fn) {
  subscribers.push(fn);
  return () => {
    subscribers = subscribers.filter(s => s !== fn);
  };
}

// Parse a Dapr service invocation URL into structured info
export function parseDaprUrl(url) {
  if (!url) return null;
  const match = url.match(/\/v1\.0\/invoke\/([^/]+)\/method(\/.*)/);
  if (match) {
    return {
      buildingBlock: 'Service Invocation',
      serviceId: match[1],
      method: match[2],
    };
  }
  return null;
}

// Format a human-readable description of a Dapr operation
export function formatDescription(httpMethod, daprInfo, extra = {}) {
  if (!daprInfo) return `${httpMethod} (non-Dapr call)`;

  const service = daprInfo.serviceId;
  const method = daprInfo.method;

  // Friendly descriptions for known operations
  if (service === 'catalog-service' && method === '/products' && httpMethod === 'GET') {
    return 'Fetch product catalog';
  }
  if (service === 'catalog-service' && method.startsWith('/products/') && httpMethod === 'GET') {
    return `Get product ${method.split('/').pop()}`;
  }
  if (service === 'catalog-service' && method === '/products' && httpMethod === 'POST') {
    return 'Create new product';
  }
  if (service === 'order-service' && method === '/orders' && httpMethod === 'POST') {
    return 'Create order (invokes catalog, publishes to pub/sub)';
  }
  if (service === 'order-service' && method.startsWith('/orders/') && httpMethod === 'GET') {
    return `Get order ${method.split('/').pop()}`;
  }
  if (service === 'workflow-service' && method === '/workflows/order' && httpMethod === 'POST') {
    return 'Start saga workflow (validate → reserve → pay → notify)';
  }
  if (service === 'workflow-service' && method.startsWith('/workflows/') && httpMethod === 'GET') {
    return 'Poll workflow status';
  }
  if (service === 'workflow-service' && method === '/workflows' && httpMethod === 'GET') {
    return 'Check workflow service availability';
  }

  return `${httpMethod} ${service}${method}`;
}
