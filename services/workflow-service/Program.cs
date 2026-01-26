using Dapr.Workflow;
using WorkflowService.Activities;
using WorkflowService.Models;
using WorkflowService.Workflows;

var builder = WebApplication.CreateBuilder(args);

// Add Dapr client
builder.Services.AddDaprClient();

// Register Dapr Workflow
builder.Services.AddDaprWorkflow(options =>
{
    // Register workflow
    options.RegisterWorkflow<OrderFulfillmentWorkflow>();

    // Register activities
    options.RegisterActivity<ValidateOrderActivity>();
    options.RegisterActivity<ReserveInventoryActivity>();
    options.RegisterActivity<ReleaseInventoryActivity>();
    options.RegisterActivity<ProcessPaymentActivity>();
    options.RegisterActivity<NotifyCustomerActivity>();
});

var app = builder.Build();

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "workflow-service" }));

// Start a new order fulfillment workflow
app.MapPost("/workflows/order", async (OrderRequest request, DaprWorkflowClient workflowClient) =>
{
    // Generate instance ID based on order ID for idempotency
    var instanceId = $"order-{request.OrderId}";

    try
    {
        await workflowClient.ScheduleNewWorkflowAsync(
            name: nameof(OrderFulfillmentWorkflow),
            instanceId: instanceId,
            input: request);

        return Results.Accepted(value: new
        {
            instanceId,
            orderId = request.OrderId,
            status = "Scheduled",
            message = "Order fulfillment workflow started"
        });
    }
    catch (Exception ex) when (ex.Message.Contains("already exists"))
    {
        return Results.Conflict(new
        {
            instanceId,
            orderId = request.OrderId,
            status = "Error",
            message = $"Workflow instance {instanceId} already exists"
        });
    }
});

// Get workflow status
app.MapGet("/workflows/{instanceId}", async (string instanceId, DaprWorkflowClient workflowClient) =>
{
    try
    {
        var state = await workflowClient.GetWorkflowStateAsync(instanceId);

        if (state == null)
        {
            return Results.NotFound(new { instanceId, message = "Workflow not found" });
        }

        var statusString = state.RuntimeStatus.ToString();

        return Results.Ok(new
        {
            instanceId,
            status = statusString,
            createdAt = state.CreatedAt,
            lastUpdatedAt = state.LastUpdatedAt,
            input = state.ReadInputAs<OrderRequest>(),
            output = statusString == "Completed"
                ? state.ReadOutputAs<OrderResult>()
                : null,
            failureDetails = statusString == "Failed"
                ? state.FailureDetails?.ErrorMessage
                : null
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error retrieving workflow state: {ex.Message}");
    }
});

// List available workflows (info endpoint)
app.MapGet("/workflows", () => Results.Ok(new
{
    availableWorkflows = new[]
    {
        new
        {
            name = "OrderFulfillmentWorkflow",
            description = "4-step saga: Validate -> Reserve Inventory -> Process Payment -> Notify Customer",
            endpoint = "POST /workflows/order",
            activities = new[] { "ValidateOrderActivity", "ReserveInventoryActivity", "ProcessPaymentActivity", "NotifyCustomerActivity" },
            compensation = new[] { "ReleaseInventoryActivity (triggered on payment failure)" }
        }
    }
}));

app.Run();
