using Dapr.Workflow;
using WorkflowService.Activities;
using WorkflowService.Models;

namespace WorkflowService.Workflows;

/// <summary>
/// Order fulfillment workflow implementing the saga pattern with compensation
///
/// Steps:
/// 1. Validate order data
/// 2. Reserve inventory (with compensation: release)
/// 3. Process payment (triggers compensation on failure)
/// 4. Notify customer
/// </summary>
public class OrderFulfillmentWorkflow : Workflow<OrderRequest, OrderResult>
{
    public override async Task<OrderResult> RunAsync(WorkflowContext context, OrderRequest input)
    {
        Console.WriteLine($"[Workflow] Starting order fulfillment workflow for order {input.OrderId}");

        // Step 1: Validate order
        Console.WriteLine($"[Workflow] Step 1: Validating order {input.OrderId}");
        var isValid = await context.CallActivityAsync<bool>(
            nameof(ValidateOrderActivity),
            input);

        if (!isValid)
        {
            Console.WriteLine($"[Workflow] Order {input.OrderId} validation failed");
            return new OrderResult(
                input.OrderId,
                Status: "Failed",
                Message: "Order validation failed - check required fields");
        }

        // Step 2: Reserve inventory
        Console.WriteLine($"[Workflow] Step 2: Reserving inventory for order {input.OrderId}");
        var reservation = await context.CallActivityAsync<InventoryReservation>(
            nameof(ReserveInventoryActivity),
            input);

        if (!reservation.Success)
        {
            Console.WriteLine($"[Workflow] Inventory reservation failed for order {input.OrderId}: {reservation.Message}");
            return new OrderResult(
                input.OrderId,
                Status: "Failed",
                Message: $"Inventory reservation failed: {reservation.Message}");
        }

        // Step 3: Process payment
        Console.WriteLine($"[Workflow] Step 3: Processing payment for order {input.OrderId}");
        var paymentResult = await context.CallActivityAsync<PaymentResult>(
            nameof(ProcessPaymentActivity),
            (input, reservation));

        if (!paymentResult.Success)
        {
            // COMPENSATION: Release reserved inventory
            Console.WriteLine($"[Workflow] Payment failed for order {input.OrderId}, triggering compensation");
            await context.CallActivityAsync<bool>(
                nameof(ReleaseInventoryActivity),
                reservation);

            return new OrderResult(
                input.OrderId,
                Status: "Failed",
                Message: $"Payment failed: {paymentResult.Message}. Inventory has been released.");
        }

        // Step 4: Notify customer (fire-and-forget)
        var totalAmount = (reservation.UnitPrice ?? 0) * input.Quantity;
        Console.WriteLine($"[Workflow] Step 4: Notifying customer for order {input.OrderId}");

        var notificationRequest = new NotificationRequest(
            input.OrderId,
            input.CustomerEmail,
            input.CustomerName,
            reservation.ProductName ?? input.ProductId,
            input.Quantity,
            totalAmount,
            "Completed");

        await context.CallActivityAsync<bool>(
            nameof(NotifyCustomerActivity),
            notificationRequest);

        // Workflow completed successfully
        Console.WriteLine($"[Workflow] Order {input.OrderId} fulfilled successfully. Total: ${totalAmount}");

        return new OrderResult(
            input.OrderId,
            Status: "Completed",
            Message: $"Order fulfilled successfully. Transaction: {paymentResult.TransactionId}",
            TotalAmount: totalAmount);
    }
}
