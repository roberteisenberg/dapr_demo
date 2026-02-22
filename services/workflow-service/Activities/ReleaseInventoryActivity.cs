using Dapr.Actors;
using Dapr.Actors.Client;
using Dapr.Workflow;
using WorkflowService.Models;

namespace WorkflowService.Activities;

/// <summary>
/// Compensation activity: releases reserved inventory via the ProductActor (Phase 12).
/// Called when fraud check fails or payment processing fails.
/// </summary>
public class ReleaseInventoryActivity : WorkflowActivity<InventoryReservation, bool>
{
    private readonly ILogger<ReleaseInventoryActivity> _logger;

    public ReleaseInventoryActivity(ILogger<ReleaseInventoryActivity> logger)
    {
        _logger = logger;
    }

    public override async Task<bool> RunAsync(WorkflowActivityContext context, InventoryReservation input)
    {
        _logger.LogInformation("COMPENSATION: Releasing inventory for order {OrderId}: {Quantity}x {ProductId}",
            input.OrderId, input.Quantity, input.ProductId);

        try
        {
            // Release stock via ProductActor
            var actorId = new ActorId(input.ProductId);
            var proxy = ActorProxy.Create(actorId, "ProductActorType");
            var result = await proxy.InvokeMethodAsync<ActorReleaseRequest, ActorReleaseResponse>(
                "Release",
                new ActorReleaseRequest(input.Quantity));

            if (!result.Success)
            {
                _logger.LogError("COMPENSATION FAILED: Actor release failed for {ProductId}: {Message}",
                    input.ProductId, result.Message);
                return false;
            }

            _logger.LogInformation("COMPENSATION COMPLETE: Released {Quantity}x {ProductId} via actor. Stock now: {Stock}",
                input.Quantity, input.ProductId, result.RemainingStock);

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "COMPENSATION FAILED: Could not release inventory for order {OrderId}", input.OrderId);
            return false;
        }
    }
}
