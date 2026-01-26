using Dapr.Client;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Publishes order notification to pub/sub for notification-service
/// </summary>
public class NotifyCustomerActivity : WorkflowActivity<NotificationRequest, bool>
{
    private readonly DaprClient _daprClient;
    private readonly ILogger<NotifyCustomerActivity> _logger;

    public NotifyCustomerActivity(DaprClient daprClient, ILogger<NotifyCustomerActivity> logger)
    {
        _daprClient = daprClient;
        _logger = logger;
    }

    public override async Task<bool> RunAsync(WorkflowActivityContext context, NotificationRequest input)
    {
        _logger.LogInformation("Publishing order notification for {OrderId} to {CustomerEmail}",
            input.OrderId, input.CustomerEmail);

        try
        {
            // Publish to pub/sub topic "orders" (same topic notification-service subscribes to)
            await _daprClient.PublishEventAsync(
                "pubsub",
                "orders",
                new
                {
                    orderId = input.OrderId,
                    customerEmail = input.CustomerEmail,
                    customerName = input.CustomerName,
                    productName = input.ProductName,
                    quantity = input.Quantity,
                    totalAmount = input.TotalAmount,
                    status = input.Status,
                    timestamp = DateTime.UtcNow
                });

            _logger.LogInformation("Notification published for order {OrderId}", input.OrderId);
            return true;
        }
        catch (Exception ex)
        {
            // Fire-and-forget: don't fail the workflow if notification fails
            _logger.LogError(ex, "Failed to publish notification for order {OrderId}", input.OrderId);
            return false;
        }
    }
}
