using Dapr.Client;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Compensation activity: releases reserved inventory by incrementing stock
/// </summary>
public class ReleaseInventoryActivity : WorkflowActivity<InventoryReservation, bool>
{
    private readonly DaprClient _daprClient;
    private readonly ILogger<ReleaseInventoryActivity> _logger;

    public ReleaseInventoryActivity(DaprClient daprClient, ILogger<ReleaseInventoryActivity> logger)
    {
        _daprClient = daprClient;
        _logger = logger;
    }

    public override async Task<bool> RunAsync(WorkflowActivityContext context, InventoryReservation input)
    {
        _logger.LogInformation("COMPENSATION: Releasing inventory for order {OrderId}: {Quantity}x {ProductId}",
            input.OrderId, input.Quantity, input.ProductId);

        try
        {
            // Get current product state
            var product = await _daprClient.InvokeMethodAsync<Product>(
                HttpMethod.Get,
                "catalog-service",
                $"products/{input.ProductId}");

            if (product == null)
            {
                _logger.LogError("Cannot release inventory: Product {ProductId} not found", input.ProductId);
                return false;
            }

            // Restore stock (release reservation)
            var updatedProduct = product with { Stock = product.Stock + input.Quantity };
            await _daprClient.InvokeMethodAsync(
                HttpMethod.Put,
                "catalog-service",
                $"products/{input.ProductId}",
                updatedProduct);

            _logger.LogInformation("COMPENSATION COMPLETE: Released {Quantity}x {ProductId}. Stock: {OldStock} -> {NewStock}",
                input.Quantity, input.ProductId, product.Stock, updatedProduct.Stock);

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "COMPENSATION FAILED: Could not release inventory for order {OrderId}", input.OrderId);
            return false;
        }
    }
}
