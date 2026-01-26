using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Validates order request fields before processing
/// </summary>
public class ValidateOrderActivity : WorkflowActivity<OrderRequest, bool>
{
    private readonly ILogger<ValidateOrderActivity> _logger;

    public ValidateOrderActivity(ILogger<ValidateOrderActivity> logger)
    {
        _logger = logger;
    }

    public override Task<bool> RunAsync(WorkflowActivityContext context, OrderRequest input)
    {
        _logger.LogInformation("Validating order {OrderId}", input.OrderId);

        // Validate required fields
        if (string.IsNullOrWhiteSpace(input.OrderId))
        {
            _logger.LogWarning("Validation failed: OrderId is required");
            return Task.FromResult(false);
        }

        if (string.IsNullOrWhiteSpace(input.ProductId))
        {
            _logger.LogWarning("Validation failed: ProductId is required");
            return Task.FromResult(false);
        }

        if (input.Quantity <= 0)
        {
            _logger.LogWarning("Validation failed: Quantity must be greater than 0");
            return Task.FromResult(false);
        }

        if (string.IsNullOrWhiteSpace(input.CustomerEmail))
        {
            _logger.LogWarning("Validation failed: CustomerEmail is required");
            return Task.FromResult(false);
        }

        _logger.LogInformation("Order {OrderId} validated successfully", input.OrderId);
        return Task.FromResult(true);
    }
}
