using Dapr.Actors;
using Dapr.Actors.Client;
using Dapr.Client;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Reserves inventory via the ProductActor (Phase 12).
/// Product metadata (name, price, category) is fetched via regular HTTP invocation.
/// Stock reservation uses the actor for turn-based concurrency — no race conditions.
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
            // Step 1: Get product metadata from catalog-service (regular HTTP)
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

            // Step 2: Reserve stock via ProductActor (turn-based concurrency)
            var actorId = new ActorId(input.ProductId);
            var proxy = ActorProxy.Create(actorId, "ProductActorType");
            var reservation = await proxy.InvokeMethodAsync<ActorReserveRequest, ActorReserveResponse>(
                "Reserve",
                new ActorReserveRequest(input.Quantity));

            if (!reservation.Success)
            {
                _logger.LogWarning("Actor reservation failed for {ProductId}: {Message}",
                    input.ProductId, reservation.Message);
                return new InventoryReservation(
                    input.OrderId,
                    input.ProductId,
                    input.Quantity,
                    Success: false,
                    Message: reservation.Message);
            }

            _logger.LogInformation("Reserved {Quantity}x {ProductId} for order {OrderId} via actor. Remaining stock: {Stock}",
                input.Quantity, input.ProductId, input.OrderId, reservation.RemainingStock);

            return new InventoryReservation(
                input.OrderId,
                input.ProductId,
                input.Quantity,
                Success: true,
                Message: "Inventory reserved successfully",
                UnitPrice: product.Price,
                ProductName: product.Name,
                ProductCategory: product.Category);
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
