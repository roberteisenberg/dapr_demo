namespace WorkflowService.Models;

/// <summary>
/// Input for the order fulfillment workflow
/// </summary>
public record OrderRequest(
    string OrderId,
    string ProductId,
    int Quantity,
    string CustomerName,
    string CustomerEmail
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
    int Stock
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
    string? ProductName = null
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
/// Result of AI fraud check activity (via Dapr Conversation API)
/// </summary>
public record FraudCheckResult(
    string OrderId,
    bool Approved,
    string RiskLevel,       // "low", "medium", "high", or "unknown"
    string? Reasoning = null
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
