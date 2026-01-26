using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Simulates payment processing with configurable failure scenarios
/// </summary>
public class ProcessPaymentActivity : WorkflowActivity<(OrderRequest Order, InventoryReservation Reservation), PaymentResult>
{
    private readonly ILogger<ProcessPaymentActivity> _logger;
    private static readonly Random _random = new();

    public ProcessPaymentActivity(ILogger<ProcessPaymentActivity> logger)
    {
        _logger = logger;
    }

    public override async Task<PaymentResult> RunAsync(
        WorkflowActivityContext context,
        (OrderRequest Order, InventoryReservation Reservation) input)
    {
        var (order, reservation) = input;
        var totalAmount = (reservation.UnitPrice ?? 0) * order.Quantity;

        _logger.LogInformation("Processing payment for order {OrderId}: ${Amount}",
            order.OrderId, totalAmount);

        // Simulate payment gateway latency
        await Task.Delay(500);

        // Business rule: fail if amount exceeds $10,000
        if (totalAmount > 10000)
        {
            _logger.LogWarning("Payment failed for order {OrderId}: Amount ${Amount} exceeds limit of $10,000",
                order.OrderId, totalAmount);
            return new PaymentResult(
                order.OrderId,
                Success: false,
                Message: $"Payment amount ${totalAmount} exceeds maximum allowed ($10,000)");
        }

        // 10% random failure for demo purposes (to show compensation)
        if (_random.Next(100) < 10)
        {
            _logger.LogWarning("Payment failed for order {OrderId}: Simulated random failure",
                order.OrderId);
            return new PaymentResult(
                order.OrderId,
                Success: false,
                Message: "Payment declined by processor (simulated failure)");
        }

        // Generate transaction ID
        var transactionId = $"TXN-{Guid.NewGuid():N}"[..20].ToUpper();

        _logger.LogInformation("Payment successful for order {OrderId}: TransactionId={TransactionId}",
            order.OrderId, transactionId);

        return new PaymentResult(
            order.OrderId,
            Success: true,
            TransactionId: transactionId,
            Message: $"Payment of ${totalAmount} processed successfully");
    }
}
