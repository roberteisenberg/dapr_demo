namespace WorkflowService.Models;

/// <summary>
/// Input for the order fulfillment workflow
/// </summary>
public record OrderRequest(
    string OrderId,
    string ProductId,
    int Quantity,
    string CustomerName,
    string CustomerEmail,
    string? ShippingAddress = null,
    bool SkipFraudCheck = false
);

/// <summary>
/// Output from the order fulfillment workflow
/// </summary>
public record OrderResult(
    string OrderId,
    string Status,
    string? Message = null,
    decimal? TotalAmount = null
);

/// <summary>
/// Product data from catalog-service
/// </summary>
public record Product(
    string Id,
    string Name,
    string? Description,
    decimal Price,
    int Stock,
    string? Category = null
);

/// <summary>
/// Result of inventory reservation activity
/// </summary>
public record InventoryReservation(
    string OrderId,
    string ProductId,
    int Quantity,
    bool Success,
    string? Message = null,
    decimal? UnitPrice = null,
    string? ProductName = null,
    string? ProductCategory = null
);

/// <summary>
/// Result of payment processing activity
/// </summary>
public record PaymentResult(
    string OrderId,
    bool Success,
    string? TransactionId = null,
    string? Message = null
);

/// <summary>
/// Result of AI fraud check activity (via Dapr Conversation API).
/// Returns a score (0-100) rather than binary approved/rejected — the workflow
/// decides the threshold (>= 80 = reject). This lets humans calibrate trust.
/// </summary>
public record FraudCheckResult(
    string OrderId,
    int Score,              // 0-100 fraud risk score
    string RiskLevel,       // "low" (0-39), "medium" (40-69), "high" (70-79), "critical" (80+), or "unknown"
    string? Reasoning = null
);

/// <summary>
/// Request to record a completed order in the order-service state store
/// </summary>
public record RecordOrderRequest(
    string OrderId,
    string ProductId,
    string? ProductName,
    string? ProductCategory,
    int Quantity,
    decimal? Price,
    decimal? Total,
    string Status,
    string CustomerName,
    string CustomerEmail,
    string? ShippingAddress = null,
    string? OrderTimestamp = null,
    string? PaymentTransactionId = null,
    int? FraudScore = null,
    string? FraudReasoning = null
);

/// <summary>
/// Notification request for customer
/// </summary>
public record NotificationRequest(
    string OrderId,
    string CustomerEmail,
    string CustomerName,
    string ProductName,
    int Quantity,
    decimal TotalAmount,
    string Status
);
