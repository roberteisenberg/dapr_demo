using Dapr.Client;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Records the completed order in the order-service state store via Dapr service invocation.
/// Fire-and-forget: don't fail the workflow if recording fails.
/// </summary>
public class RecordOrderActivity : WorkflowActivity<RecordOrderRequest, bool>
{
    private readonly DaprClient _daprClient;
    private readonly ILogger<RecordOrderActivity> _logger;

    public RecordOrderActivity(DaprClient daprClient, ILogger<RecordOrderActivity> logger)
    {
        _daprClient = daprClient;
        _logger = logger;
    }

    public override async Task<bool> RunAsync(WorkflowActivityContext context, RecordOrderRequest input)
    {
        _logger.LogInformation("Recording order {OrderId} to order-service state store", input.OrderId);

        try
        {
            await _daprClient.InvokeMethodAsync(
                HttpMethod.Post,
                "order-service",
                "orders/record",
                input);

            _logger.LogInformation("Order {OrderId} recorded successfully", input.OrderId);
            return true;
        }
        catch (Exception ex)
        {
            // Fire-and-forget: don't fail the workflow if recording fails
            _logger.LogError(ex, "Failed to record order {OrderId}", input.OrderId);
            return false;
        }
    }
}
