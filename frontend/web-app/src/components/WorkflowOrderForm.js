import React, { useState, useEffect } from 'react';
import { startWorkflow, getWorkflowStatus } from '../services/api';

function WorkflowOrderForm({ product, onComplete, onCancel, skipFraudCheck = false }) {
  const [quantity, setQuantity] = useState(1);
  const [customerName, setCustomerName] = useState('');
  const [customerEmail, setCustomerEmail] = useState('');
  const [shippingAddress, setShippingAddress] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [workflowState, setWorkflowState] = useState(null);
  const [instanceId, setInstanceId] = useState(null);

  // Poll for workflow status once started
  useEffect(() => {
    let interval;
    if (instanceId && workflowState?.status !== 'Completed' && workflowState?.status !== 'Failed') {
      interval = setInterval(async () => {
        try {
          const status = await getWorkflowStatus(instanceId);
          setWorkflowState(status);
          if (status.status === 'Completed' || status.status === 'Failed') {
            clearInterval(interval);
          }
        } catch (err) {
          console.error('Error polling workflow status:', err);
        }
      }, 1000);
    }
    return () => clearInterval(interval);
  }, [instanceId, workflowState?.status]);

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!customerName.trim()) {
      setError('Customer name is required');
      return;
    }

    if (!customerEmail.trim() || !customerEmail.includes('@')) {
      setError('Valid email is required');
      return;
    }

    if (quantity < 1 || quantity > product.stock) {
      setError(`Quantity must be between 1 and ${product.stock}`);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const orderId = `order-${Date.now()}`;
      const orderData = {
        orderId,
        productId: product.id,
        quantity: parseInt(quantity, 10),
        customerName: customerName.trim(),
        customerEmail: customerEmail.trim(),
        shippingAddress: shippingAddress.trim() || undefined,
        skipFraudCheck,
      };

      const result = await startWorkflow(orderData);
      console.log('Workflow started:', result);
      setInstanceId(result.instanceId);
      setWorkflowState({ status: 'Running', message: 'Workflow started...' });
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'Failed to start workflow';
      setError(errorMessage);
      console.error('Error starting workflow:', err);
      setLoading(false);
    }
  };

  const total = (product.price * quantity).toFixed(2);
  const isComplete = workflowState?.status === 'Completed';
  const isFailed = workflowState?.status === 'Failed';
  const isRunning = instanceId && !isComplete && !isFailed;

  // Determine saga step from workflow output
  const getSagaSteps = () => {
    const steps = [
      { name: 'Validate Order', status: 'pending' },
      { name: 'Reserve Inventory', status: 'pending' },
      { name: skipFraudCheck ? 'Check Fraud (skipped)' : 'Check Fraud', status: 'pending' },
      { name: 'Process Payment', status: 'pending' },
      { name: 'Send Notification', status: 'pending' },
      { name: 'Record Order', status: 'pending' },
    ];

    if (!workflowState) return steps;

    const output = workflowState.output;
    if (output?.status === 'Completed') {
      return steps.map(s => ({ ...s, status: 'completed' }));
    }

    if (output?.status === 'Failed') {
      const message = output.message || '';
      if (message.includes('validation')) {
        steps[0].status = 'failed';
      } else if (message.includes('Inventory') && !message.includes('fraud')) {
        steps[0].status = 'completed';
        steps[1].status = message.includes('released') ? 'compensated' : 'failed';
      } else if (message.includes('fraud')) {
        steps[0].status = 'completed';
        steps[1].status = 'compensated';
        steps[2].status = 'failed';
      } else if (message.includes('Payment')) {
        steps[0].status = 'completed';
        steps[1].status = 'compensated';
        steps[2].status = 'completed';
        steps[3].status = 'failed';
      }
      return steps;
    }

    // Running state - mark first step as in-progress
    if (isRunning) {
      steps[0].status = 'running';
    }

    return steps;
  };

  const getStepIcon = (status) => {
    switch (status) {
      case 'completed': return '✓';
      case 'failed': return '✗';
      case 'compensated': return '↩';
      case 'running': return '●';
      default: return '○';
    }
  };

  const getStepClass = (status) => {
    switch (status) {
      case 'completed': return 'step-completed';
      case 'failed': return 'step-failed';
      case 'compensated': return 'step-compensated';
      case 'running': return 'step-running';
      default: return 'step-pending';
    }
  };

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && !isRunning && onCancel()}>
      <div className="modal workflow-modal">
        <h2>Order with Workflow</h2>
        <p className="workflow-subtitle">{skipFraudCheck ? 'Saga Pattern — Manual Review' : 'Saga Pattern with AI Fraud Check'}</p>

        {instanceId ? (
          <div className="workflow-status">
            <div className="saga-steps">
              {getSagaSteps().map((step, index) => (
                <div key={index} className={`saga-step ${getStepClass(step.status)}`}>
                  <span className="step-icon">{getStepIcon(step.status)}</span>
                  <span className="step-name">{step.name}</span>
                </div>
              ))}
            </div>

            {isRunning && (
              <div className="workflow-running">
                <div className="spinner"></div>
                <p>Processing order...</p>
              </div>
            )}

            {isComplete && workflowState.output?.status === 'Completed' && (
              <div className="workflow-success">
                <h3>Order Pending Shipment</h3>
                <p>Payment processed. Order is awaiting shipment review.</p>
                {workflowState.output?.totalAmount && (
                  <p className="total-charged">Total: ${workflowState.output.totalAmount.toFixed(2)}</p>
                )}
                <button onClick={onComplete} className="submit-button">
                  Done
                </button>
              </div>
            )}

            {(isComplete && workflowState.output?.status === 'Failed') || isFailed ? (
              <div className="workflow-failed">
                <h3>Order Failed</h3>
                <p>{workflowState.output?.message || 'Workflow failed'}</p>
                <p className="compensation-note">Inventory has been automatically restored.</p>
                <button onClick={onCancel} className="cancel-button">
                  Close
                </button>
              </div>
            ) : null}
          </div>
        ) : (
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label>Product:</label>
              <p className="product-name">{product.name}</p>
              <p className="product-price">${product.price.toFixed(2)} each</p>
            </div>

            <div className="form-group">
              <label htmlFor="customerName">Your Name:</label>
              <input
                type="text"
                id="customerName"
                value={customerName}
                onChange={(e) => setCustomerName(e.target.value)}
                placeholder="John Doe"
                required
                disabled={loading}
              />
            </div>

            <div className="form-group">
              <label htmlFor="customerEmail">Email:</label>
              <input
                type="email"
                id="customerEmail"
                value={customerEmail}
                onChange={(e) => setCustomerEmail(e.target.value)}
                placeholder="john@example.com"
                required
                disabled={loading}
              />
            </div>

            <div className="form-group">
              <label htmlFor="shippingAddress">Shipping Address:</label>
              <input
                type="text"
                id="shippingAddress"
                value={shippingAddress}
                onChange={(e) => setShippingAddress(e.target.value)}
                placeholder="123 Main St, Anytown, ST 12345"
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
              {parseFloat(total) > 10000 && (
                <span className="hint warning">Note: Orders over $10,000 will fail (demo)</span>
              )}
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
                className="submit-button workflow-submit"
                disabled={loading}
              >
                {loading ? 'Starting...' : 'Start Workflow'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

export default WorkflowOrderForm;
