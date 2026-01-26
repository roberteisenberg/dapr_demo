using Dapr.Client;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Reserves inventory by decrementing stock in catalog-service
/// </summary>
public class ReserveInventoryActivity : WorkflowActivity<OrderRequest, InventoryReservation>
{
    private readonly DaprClient _daprClient;
    private readonly ILogger<ReserveInventoryActivity> _logger;

    public ReserveInventoryActivity(DaprClient daprClient, ILogger<ReserveInventoryActivity> logger)
    {
        _daprClient = daprClient;
        _logger = logger;
    }

    public override async Task<InventoryReservation> RunAsync(WorkflowActivityContext context, OrderRequest input)
    {
        _logger.LogInformation("Reserving inventory for order {OrderId}: {Quantity}x {ProductId}",
            input.OrderId, input.Quantity, input.ProductId);

        try
        {
            // Get product from catalog-service
            var product = await _daprClient.InvokeMethodAsync<Product>(
                HttpMethod.Get,
                "catalog-service",
                $"products/{input.ProductId}");

            if (product == null)
            {
                _logger.LogWarning("Product {ProductId} not found", input.ProductId);
                return new InventoryReservation(
                    input.OrderId,
                    input.ProductId,
                    input.Quantity,
                    Success: false,
                    Message: $"Product {input.ProductId} not found");
            }

            // Check stock availability
            if (product.Stock < input.Quantity)
            {
                _logger.LogWarning("Insufficient stock for {ProductId}: available={Stock}, requested={Quantity}",
                    input.ProductId, product.Stock, input.Quantity);
                return new InventoryReservation(
                    input.OrderId,
                    input.ProductId,
                    input.Quantity,
                    Success: false,
                    Message: $"Insufficient stock: available={product.Stock}, requested={input.Quantity}");
            }

            // Update stock (reserve inventory)
            var updatedProduct = product with { Stock = product.Stock - input.Quantity };
            await _daprClient.InvokeMethodAsync(
                HttpMethod.Put,
                "catalog-service",
                $"products/{input.ProductId}",
                updatedProduct);

            _logger.LogInformation("Reserved {Quantity}x {ProductId} for order {OrderId}. Stock: {OldStock} -> {NewStock}",
                input.Quantity, input.ProductId, input.OrderId, product.Stock, updatedProduct.Stock);

            return new InventoryReservation(
                input.OrderId,
                input.ProductId,
                input.Quantity,
                Success: true,
                Message: "Inventory reserved successfully",
                UnitPrice: product.Price,
                ProductName: product.Name);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to reserve inventory for order {OrderId}", input.OrderId);
            return new InventoryReservation(
                input.OrderId,
                input.ProductId,
                input.Quantity,
                Success: false,
                Message: $"Failed to reserve inventory: {ex.Message}");
        }
    }
}
